// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// 信頼できる第三者を介さずに、共有オブジェクトを使用してオブジェクトを
/// アトミックにスワップするためのエスクロー。
///
/// プロトコルは3つのフェーズで構成されます:
///
/// 1. 一方の当事者がオブジェクトを`lock`し、`Locked`オブジェクトとその`Key`を取得します。
///    この当事者は、もう一方の当事者が第2段階を完了する前に失速した場合に、
///    ライブネスを維持するためにオブジェクトを`unlock`できます。
///
/// 2. もう一方の当事者は、公開アクセス可能な共有`Escrow`オブジェクトを登録します。
///    これにより、最初の当事者がスワップを完了するのを待つ間、
///    彼らのオブジェクトも特定のバージョンで効果的にロックされます。
///    2番目の当事者は、ライブネスを維持するためにオブジェクトの返却を要求できます。
///
/// 3. 最初の当事者は、ロックされたオブジェクトとそのキーを共有`Escrow`オブジェクトに送信します。
///    これにより、すべての条件が満たされていればスワップが完了します:
///
///    - スワップトランザクションの送信者が`Escrow`の受信者であること。
///
///    - エスクロー内の目的のオブジェクトのキー(`exchange_key`)が、
///      スワップで提供されたキーと一致すること。
///
///    - スワップで提供されたキーが`Locked<U>`をアンロックすること。
module escrow::shared;

use escrow::lock::{Locked, Key};
use sui::dynamic_object_field as dof;
use sui::event;

/// エスクローされたオブジェクトを保持するDOFの`name`。
/// エスクローされたオブジェクトを簡単に見つけられるようにします。
public struct EscrowedObjectKey has copy, drop, store {}

/// エスクローで保持されるオブジェクト
///
/// エスクローされたオブジェクトは、引き続き検索できるように動的オブジェクトフィールドとして追加されます。
public struct Escrow<phantom T: key + store> has key, store {
    id: UID,
    /// `escrowed`の所有者
    sender: address,
    /// 意図された受信者
    recipient: address,
    /// 送信者が受信者から欲しいオブジェクトのロックを解除するキーのID。
    exchange_key: ID,
}

// === エラーコード ===

/// 2つのエスクローされたオブジェクトの`sender`と`recipient`が一致しません
const EMismatchedSenderRecipient: u64 = 0;

/// 2つのエスクローされたオブジェクトの`exchange_for`フィールドが一致しません
const EMismatchedExchangeObject: u64 = 1;

// === 公開関数 ===

//docs::#noemit
public fun create<T: key + store>(
    escrowed: T,
    exchange_key: ID,
    recipient: address,
    ctx: &mut TxContext,
) {
    let mut escrow = Escrow<T> {
        id: object::new(ctx),
        sender: ctx.sender(),
        recipient,
        exchange_key,
    };

    //docs::#noemit-pause
    event::emit(EscrowCreated {
        escrow_id: object::id(&escrow),
        key_id: exchange_key,
        sender: escrow.sender,
        recipient,
        item_id: object::id(&escrowed),
    });
    //docs::#noemit-resume

    dof::add(&mut escrow.id, EscrowedObjectKey {}, escrowed);

    transfer::public_share_object(escrow);
}
//docs::/#noemit

/// エスクローの`recipient`は`obj`をエスクローされたアイテムと交換できます
public fun swap<T: key + store, U: key + store>(
    mut escrow: Escrow<T>,
    key: Key,
    locked: Locked<U>,
    ctx: &TxContext,
): T {
    let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

    let Escrow {
        id,
        sender,
        recipient,
        exchange_key,
    } = escrow;

    assert!(recipient == ctx.sender(), EMismatchedSenderRecipient);
    assert!(exchange_key == object::id(&key), EMismatchedExchangeObject);

    // 実際のスワップを実行
    transfer::public_transfer(locked.unlock(key), sender);

    event::emit(EscrowSwapped {
        escrow_id: id.to_inner(),
    });

    id.delete();

    escrowed
}

/// `creator`はエスクローをキャンセルして、エスクローされたアイテムを取り戻すことができます
public fun return_to_sender<T: key + store>(mut escrow: Escrow<T>, ctx: &TxContext): T {
    event::emit(EscrowCancelled {
        escrow_id: object::id(&escrow),
    });

    let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

    let Escrow {
        id,
        sender,
        recipient: _,
        exchange_key: _,
    } = escrow;

    assert!(sender == ctx.sender(), EMismatchedSenderRecipient);
    id.delete();
    escrowed
}

// === イベント ===
public struct EscrowCreated has copy, drop {
    /// 作成されたエスクローのID
    escrow_id: ID,
    /// 要求されたオブジェクトをアンロックする`Key`のID。
    key_id: ID,
    /// スワップ時に`T`を受け取る送信者のID
    sender: address,
    /// エスクローされたオブジェクトの（元の）受信者
    recipient: address,
    /// エスクローされたアイテムのID
    item_id: ID,
}

public struct EscrowSwapped has copy, drop {
    escrow_id: ID,
}

public struct EscrowCancelled has copy, drop {
    escrow_id: ID,
}

// === テスト ===
#[test_only]
use sui::coin::{Self, Coin};
#[test_only]
use sui::sui::SUI;
#[test_only]
use sui::test_scenario::{Self as ts, Scenario};

#[test_only]
use escrow::lock;

#[test_only]
const ALICE: address = @0xA;
#[test_only]
const BOB: address = @0xB;
#[test_only]
const DIANE: address = @0xD;

#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts.ctx())
}

//docs::#test
#[test]
fun test_successful_swap() {
    let mut ts = ts::begin(@0x0);

    //docs::#test-pause:// テストの残り...

    // Bobは取引したいオブジェクトをロックします。
    let (i2, ik2) = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        (cid, kid)
    };

    // Aliceは、共有する意思のあるオブジェクトと、Bobから欲しいオブジェクトを
    // 保持する公開エスクローを作成します。
    let i1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        create(c, ik2, BOB, ts.ctx());
        cid
    };

    // Bobは自分のオブジェクトを提供することで応答し、代わりにAliceのオブジェクトを取得します。
    // docs::#bob
    {
        ts.next_tx(BOB);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };
    // docs::/#bob

    // docs::#finish
    // スワップからのエフェクトをコミット
    ts.next_tx(@0x0);

    // AliceはBobからオブジェクトを取得します
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
        ts::return_to_address(ALICE, c);
    };

    // BobはAliceからオブジェクトを取得します
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
        ts::return_to_address(BOB, c);
    };
    // docs::/#finish
    //docs::#test-resume

    ts::end(ts);
}
//docs::/#test

#[test]
#[expected_failure(abort_code = EMismatchedSenderRecipient)]
fun test_mismatch_sender() {
    let mut ts = ts::begin(@0x0);

    let ik2 = {
        ts.next_tx(DIANE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, DIANE);
        transfer::public_transfer(k, DIANE);
        kid
    };

    // AliceはBobと取引したい。
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        create(c, ik2, BOB, ts.ctx());
    };

    // しかし、スワップを試みるのはDianeです
    {
        ts.next_tx(DIANE);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, DIANE);
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = EMismatchedExchangeObject)]
fun test_mismatch_object() {
    let mut ts = ts::begin(@0x0);

    {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
    };

    // AliceはBobと取引したいが、Aliceが要求したオブジェクト（`exchange_key`経由）を
    // Bobはスワップに出していません。
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        create(c, cid, BOB, ts.ctx());
    };

    // Bobがスワップを完了しようとすると、Aliceの要件を満たせないため失敗します。
    {
        ts.next_tx(BOB);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = EMismatchedExchangeObject)]
fun test_object_tamper() {
    let mut ts = ts::begin(@0x0);

    // Bobは自分のオブジェクトをロックします。
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Aliceはエスクローを設定します
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        create(c, ik2, BOB, ts.ctx());
    };

    // Bobは心変わりし、オブジェクトをアンロックしてスワップを開始する前に改ざんしますが、
    // Bobが改ざんを隠すことはできません。
    {
        ts.next_tx(BOB);
        let k: Key = ts.take_from_sender();
        let l: Locked<Coin<SUI>> = ts.take_from_sender();
        let mut c = lock::unlock(l, k);

        let _dust = c.split(1, ts.ctx());
        let (l, k) = lock::lock(c, ts.ctx());
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let c = escrow.swap(k, l, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    abort 1337
}

#[test]
fun test_return_to_sender() {
    let mut ts = ts::begin(@0x0);

    // Aliceは取引したいオブジェクトを提示します
    let cid = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let i = object::id_from_address(@0x0);
        create(c, i, BOB, ts.ctx());
        cid
    };

    // ...しかし心変わりして取り戻します
    {
        ts.next_tx(ALICE);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let c = escrow.return_to_sender(ts.ctx());

        transfer::public_transfer(c, ALICE);
    };

    ts.next_tx(@0x0);

    // その後、Aliceはそれにアクセスできます。
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, cid);
        ts::return_to_address(ALICE, c)
    };

    ts::end(ts);
}

#[test]
#[expected_failure]
fun test_return_to_sender_failed_swap() {
    let mut ts = ts::begin(@0x0);

    // Bobは自分のオブジェクトをロックします。
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Aliceは、共有する意思のあるオブジェクトと、Bobから欲しいオブジェクトを
    // 保持する公開エスクローを作成します。
    {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        create(c, ik2, BOB, ts.ctx());
    };

    // ...しかし、その後心変わりします
    {
        ts.next_tx(ALICE);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let c = escrow.return_to_sender(ts.ctx());
        transfer::public_transfer(c, ALICE);
    };

    // Bobがスワップを完了しようとしても、今度は失敗します。
    {
        ts.next_tx(BOB);
        let escrow: Escrow<Coin<SUI>> = ts.take_shared();
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        let c = escrow.swap(k2, l2, ts.ctx());

        transfer::public_transfer(c, BOB);
    };

    abort 1337
}
