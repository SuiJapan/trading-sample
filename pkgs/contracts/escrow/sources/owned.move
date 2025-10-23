// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// 単一所有者トランザクションを使用したオブジェクトのアトミックスワップのためのエスクローです。
/// 安全性ではなく、活性（liveness）のために第三者を信頼します。
///
/// エスクローを介したスワップは、3つのフェーズで進行します:
///
/// 1. 両当事者はそれぞれのオブジェクトを`lock`し、`Locked`オブジェクトと`Key`を取得します。
///    もし相手方が第2ステージを完了する前に停滞した場合、活性を維持するために、
///    各当事者は自分のオブジェクトを`unlock`できます。
///
/// 2. 両当事者は`Escrow`オブジェクトを管理者（custodian）に登録します。これには
///    ロックされたオブジェクトとそのキーを渡す必要があります。キーはオブジェクトのロックを
///    解除するために消費されますが、そのIDは記憶され、管理者が正しいオブジェクトが
///    交換されることを保証できるようにします。管理者は活性を維持するために信頼されます。
///
/// 3. 管理者は、以下のすべての条件が満たされている限り、ロックされたオブジェクトを交換します:
///
///    - 一方のエスクローの送信者（sender）がもう一方の受信者（recipient）であり、その逆も同様であること。
///      これが真でない場合、管理者はこのスワップを誤ってペアリングしています。
///
///    - 要求するオブジェクトのキー（`exchange_key`）が、もう一方のオブジェクトがロックされた
///      キー（`escrowed_key`）と一致し、その逆も同様であること。
///
///      これが真でない場合、管理者が誤ったエскローをペアリングしたか、
///      または一方の当事者がオブジェクトをロックした後に改ざんしたことを意味します。
///
///      問題のキーは、それぞれのオブジェクトが管理者に送られる直前に
///      存在していた`Locked`オブジェクトのロックを解除した`Key`オブジェクトのIDです。
module escrow::owned;

use escrow::lock::{Locked, Key};

/// エスクローで保持されるオブジェクト
public struct Escrow<T: key + store> has key {
    id: UID,
    /// `escrowed`の所有者
    sender: address,
    /// 想定される受信者
    recipient: address,
    /// 送信者が受信者から受け取りたいオブジェクトのロックを開けるキーのID
    exchange_key: ID,
    /// エスクローされる前に、エスクロー対象オブジェクトをロックしたキーのID
    escrowed_key: ID,
    /// エスクローされたオブジェクト
    escrowed: T,
}

// === エラーコード ===

/// 2つのエスクローオブジェクトの`sender`と`recipient`が一致しない
const EMismatchedSenderRecipient: u64 = 0;

/// 2つのエスクローオブジェクトの`exchange_key`フィールドが一致しない
const EMismatchedExchangeObject: u64 = 1;

// === 公開関数 ===

/// `ctx.sender()`は、`exchange_key`によって参照されるオブジェクトと引き換えに、
/// ロックされたオブジェクト`locked`を`recipient`と交換することを要求します。
/// このスワップは、活性を維持するために信頼される第三者である`custodian`によって実行されますが、
/// 安全性については信頼されません（管理者が実行できる唯一のアクションは、スワップを正常に進行させることです）。
///
/// `locked`は、管理者へ送信される前に対応する`key`でアンロックされますが、
/// 元のオブジェクトはスワップが成功裏に実行されるか、管理者がオブジェクトを返却するまで
/// アクセスできません。
///
/// `exchange_key`は、送信者が望むオブジェクトのロックを解除する`Key`のIDです。
/// キーに基づいてスワップをゲートすることで、送信者のオブジェクトがエスクローで保持された後に
/// 目的のオブジェクトが改ざんされた場合にスワップが成功しないことを保証します。
/// なぜなら、受信者はオブジェクトを改ざんするためにキーを消費する必要があり、
/// オブジェクトを再ロックした場合、それは異なる互換性のないキーで保護されるためです。
public fun create<T: key + store>(
    key: Key,
    locked: Locked<T>,
    exchange_key: ID,
    recipient: address,
    custodian: address,
    ctx: &mut TxContext,
) {
    let escrow = Escrow {
        id: object::new(ctx),
        sender: ctx.sender(),
        recipient,
        exchange_key,
        escrowed_key: object::id(&key),
        escrowed: locked.unlock(key),
    };

    transfer::transfer(escrow, custodian);
}

/// 管理者（信頼された第三者）が2つの当事者間でスワップを実行するための関数。
/// 送信者と受信者が一致しない場合、またはそれぞれの希望するオブジェクトが一致しない場合に失敗します。
public fun swap<T: key + store, U: key + store>(obj1: Escrow<T>, obj2: Escrow<U>) {
    let Escrow {
        id: id1,
        sender: sender1,
        recipient: recipient1,
        exchange_key: exchange_key1,
        escrowed_key: escrowed_key1,
        escrowed: escrowed1,
    } = obj1;

    let Escrow {
        id: id2,
        sender: sender2,
        recipient: recipient2,
        exchange_key: exchange_key2,
        escrowed_key: escrowed_key2,
        escrowed: escrowed2,
    } = obj2;
    id1.delete();
    id2.delete();

    // 送信者と受信者が互いに一致することを確認
    assert!(sender1 == recipient2, EMismatchedSenderRecipient);
    assert!(sender2 == recipient1, EMismatchedSenderRecipient);

    // オブジェクトが互いに一致し、変更されていないこと（ロックされたままであること）を確認
    assert!(escrowed_key1 == exchange_key2, EMismatchedExchangeObject);
    assert!(escrowed_key2 == exchange_key1, EMismatchedExchangeObject);

    // 実際のスワップを実行
    transfer::public_transfer(escrowed1, recipient1);
    transfer::public_transfer(escrowed2, recipient2);
}

/// 管理者はいつでもエスクローされたオブジェクトを元の所有者に返却できます。
public fun return_to_sender<T: key + store>(obj: Escrow<T>) {
    let Escrow {
        id,
        sender,
        recipient: _,
        exchange_key: _,
        escrowed_key: _,
        escrowed,
    } = obj;
    id.delete();
    transfer::public_transfer(escrowed, sender);
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
const CUSTODIAN: address = @0xC;
#[test_only]
const DIANE: address = @0xD;

#[test_only]
fun test_coin(ts: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(42, ts::ctx(ts))
}

#[test]
fun test_successful_swap() {
    let mut ts = ts::begin(@0x0);

    // Aliceが交換したいオブジェクトをロックする
    let (i1, ik1) = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        (cid, kid)
    };

    // Bobも同様にオブジェクトをロックする
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

    // Aliceが管理者にオブジェクトを預け、エスクローで保持してもらう
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // Bobも同様に行う
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k2, l2, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // 管理者がスワップを実行する
    {
        ts.next_tx(CUSTODIAN);
        swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender(),
        );
    };

    // スワップによるエフェクトをコミットする
    ts.next_tx(@0x0);

    // AliceがBobからオブジェクトを受け取る
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
        ts::return_to_address(ALICE, c);
    };

    // BobがAliceからオブジェクトを受け取る
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
        ts::return_to_address(BOB, c);
    };

    ts.end();
}

#[test]
#[expected_failure(abort_code = EMismatchedSenderRecipient)]
fun test_mismatch_sender() {
    let mut ts = ts::begin(@0x0);

    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // AliceはBobと交換したい
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // しかしBobはDianeと交換したい
    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k2, l2, ik1, DIANE, CUSTODIAN, ts.ctx());
    };

    // 管理者がスワップをマッチングさせようとすると、失敗する
    {
        ts.next_tx(CUSTODIAN);
        swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender(),
        );
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = EMismatchedExchangeObject)]
fun test_mismatch_object() {
    let mut ts = ts::begin(@0x0);

    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
    };

    // AliceはBobと交換したいが、Aliceが要求したオブジェクト（`exchange_key`経由）は
    // Bobがスワップに出していない
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k1, l1, ik1, BOB, CUSTODIAN, ts.ctx());
    };

    {
        ts.next_tx(BOB);
        let k2: Key = ts.take_from_sender();
        let l2: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k2, l2, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // 管理者がスワップをマッチングさせようとすると、失敗する
    {
        ts.next_tx(CUSTODIAN);
        swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender(),
        );
    };

    abort 1337
}

#[test]
#[expected_failure(abort_code = EMismatchedExchangeObject)]
fun test_object_tamper() {
    let mut ts = ts::begin(@0x0);

    // Aliceが交換したいオブジェクトをロックする
    let ik1 = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, ALICE);
        transfer::public_transfer(k, ALICE);
        kid
    };

    // Bobも同様にオブジェクトをロックする
    let ik2 = {
        ts.next_tx(BOB);
        let c = test_coin(&mut ts);
        let (l, k) = lock::lock(c, ts.ctx());
        let kid = object::id(&k);
        transfer::public_transfer(l, BOB);
        transfer::public_transfer(k, BOB);
        kid
    };

    // Aliceが管理者にオブジェクトを預け、エскローで保持してもらう
    {
        ts.next_tx(ALICE);
        let k1: Key = ts.take_from_sender();
        let l1: Locked<Coin<SUI>> = ts.take_from_sender();
        create(k1, l1, ik2, BOB, CUSTODIAN, ts.ctx());
    };

    // Bobが心変わりし、オブジェクトのロックを解除して改ざんする
    {
        ts.next_tx(BOB);
        let k: Key = ts.take_from_sender();
        let l: Locked<Coin<SUI>> = ts.take_from_sender();
        let mut c = lock::unlock(l, k);

        let _dust = coin::split(&mut c, 1, ts.ctx());
        let (l, k) = lock::lock(c, ts.ctx());
        create(k, l, ik1, ALICE, CUSTODIAN, ts.ctx());
    };

    // 管理者がスワップを実行すると、Bobの不正行為を検出する
    {
        ts.next_tx(CUSTODIAN);
        swap<Coin<SUI>, Coin<SUI>>(
            ts.take_from_sender(),
            ts.take_from_sender(),
        );
    };

    abort 1337
}

#[test]
fun test_return_to_sender() {
    let mut ts = ts::begin(@0x0);

    // Aliceが交換したいオブジェクトをロックする
    let cid = {
        ts.next_tx(ALICE);
        let c = test_coin(&mut ts);
        let cid = object::id(&c);
        let (l, k) = lock::lock(c, ts.ctx());
        let i = object::id_from_address(@0x0);
        create(k, l, i, BOB, CUSTODIAN, ts.ctx());
        cid
    };

    // 管理者がそれを返送する
    {
        ts.next_tx(CUSTODIAN);
        return_to_sender<Coin<SUI>>(ts.take_from_sender());
    };

    ts.next_tx(@0x0);

    // Aliceはそれにアクセスできるようになる
    {
        let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, cid);
        ts::return_to_address(ALICE, c)
    };

    ts.end();
}
