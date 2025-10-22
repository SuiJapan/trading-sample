// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module demo::demo_bear;

use std::string::{String, utf8};
use sui::display;
use sui::package;

/// デモ用の構造体
public struct DemoBear has key, store {
    id: UID,
    name: String,
}

/// Displayを作成するためのOTW (One-Time Witness)
public struct DEMO_BEAR has drop {}

// Displayはコントラクトで直接作成するのではなく、
// PTB (Programmable Transaction Block) を使用して作成することが推奨されます。
// ここではデモ目的（ワンステップでのセットアップ）のためだけに作成しています。
fun init(otw: DEMO_BEAR, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    let keys = vector[utf8(b"name"), utf8(b"image_url"), utf8(b"description")];

    let values = vector[
        // `DemoBear`にデモ用の名前を追加しましょう
        utf8(b"{name}"),
        // 幸せそうなクマの画像を追加します。
        utf8(
            b"https://images.unsplash.com/photo-1589656966895-2f33e7653819?q=80&w=1000&auto=format&fit=crop&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Mnx8cG9sYXIlMjBiZWFyfGVufDB8fDB8fHww",
        ),
        // 説明はすべてのクマで静的（共通）です。
        utf8(b"The greatest figure for demos"),
    ];

    // `DemoBear`型の新しい`Display`オブジェクトを取得します。
    let mut display = display::new_with_fields<DemoBear>(
        &publisher,
        keys,
        values,
        ctx,
    );

    // 変更を適用するために`Display`の最初のバージョンを更新します。
    display::update_version(&mut display);

    sui::transfer::public_transfer(display, ctx.sender());
    sui::transfer::public_transfer(publisher, ctx.sender())
}

public fun new(name: String, ctx: &mut TxContext): DemoBear {
    DemoBear {
        id: object::new(ctx),
        name: name,
    }
}

