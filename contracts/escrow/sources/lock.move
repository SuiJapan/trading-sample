// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// `lock`モジュールは、`store`アビリティを持つ任意のオブジェクトをラップし、
/// 使い捨ての`Key`で保護するためのAPIを提供します。
///
/// これは、エスクロー中に特定のオブジェクトを特定の固定された状態で
/// 交換することをコミットするために使用されます。
module escrow::lock;

use sui::dynamic_object_field as dof;
use sui::event;

/// Lockedオブジェクトを保持するDOF（Dynamic Object Field）の`name`です。
/// これにより、ロックされたオブジェクトの発見可能性が向上します。
public struct LockedObjectKey has copy, drop, store {}

/// `Key`へのアクセスを要求することで`obj`へのアクセスを保護するラッパーです。
///
/// スワップに関与する可能性のあるオブジェクトが変更されないようにするために使用されます。
///
/// オブジェクトは動的オブジェクトフィールド（Dynamic Object Field）として追加されるため、
/// 後からでも検索することが可能です。
public struct Locked<phantom T: key + store> has key, store {
    id: UID,
    key: ID,
}

/// ロックされたオブジェクトを開くための鍵（`Key`を消費します）
public struct Key has key, store { id: UID }

// === エラーコード ===

/// 鍵がこのロックと一致しません。
const ELockKeyMismatch: u64 = 0;

// === 公開関数 ===

/// `obj`をロックし、それをアンロックするために使用できる鍵を取得します。
public fun lock<T: key + store>(obj: T, ctx: &mut TxContext): (Locked<T>, Key) {
    let key = Key { id: object::new(ctx) };
    let mut lock = Locked {
        id: object::new(ctx),
        key: object::id(&key),
    };

    event::emit(LockCreated {
        lock_id: object::id(&lock),
        key_id: object::id(&key),
        creator: ctx.sender(),
        item_id: object::id(&obj),
    });

    // `object`を`lock`オブジェクトのDOFとして追加します
    dof::add(&mut lock.id, LockedObjectKey {}, obj);

    (lock, key)
}

/// `locked`内のオブジェクトをアンロックし、`key`を消費します。`locked`オブジェクトに
/// 対して間違った`key`が渡された場合は失敗します。
public fun unlock<T: key + store>(mut locked: Locked<T>, key: Key): T {
    assert!(locked.key == object::id(&key), ELockKeyMismatch);
    let Key { id } = key;
    id.delete();

    let obj = dof::remove<LockedObjectKey, T>(&mut locked.id, LockedObjectKey {});

    event::emit(LockDestroyed { lock_id: object::id(&locked) });

    let Locked { id, key: _ } = locked;
    id.delete();
    obj
}

// === イベント ===
public struct LockCreated has copy, drop {
    /// `Locked`オブジェクトのID。
    lock_id: ID,
    /// `Locked`内のロックされたオブジェクトをアンロックする鍵のID。
    key_id: ID,
    /// ロックされたオブジェクトの作成者。
    creator: address,
    /// ロックされたアイテムのID。
    item_id: ID,
}

public struct LockDestroyed has copy, drop {
    /// `Locked`オブジェクトのID。
    lock_id: ID,
}

// === テスト ===
#[test_only]
use sui::coin::{Self, Coin};
#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};

#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts.ctx())
}

#[test]
fun test_lock_unlock() {
    let mut ts = ts::begin(@0xA);
    let coin = test_coin(&mut ts);

    let (lock, key) = lock(coin, ts.ctx());
    let coin = lock.unlock(key);

    coin.burn_for_testing();
    ts.end();
}

#[test]
#[expected_failure(abort_code = ELockKeyMismatch)]
fun test_lock_key_mismatch() {
    let mut ts = ts::begin(@0xA);
    let coin = test_coin(&mut ts);
    let another_coin = test_coin(&mut ts);
    let (l, _k) = lock(coin, ts.ctx());
    let (_l, k) = lock(another_coin, ts.ctx());

    let _key = l.unlock(k);
    abort 1337
}
