# エスクローAPIデモ

このデモは、イベントインデクサーとAPIを構築し、アプリのオンチェーンデータを効率的に提供する方法を紹介するために作られました。

デモのインデクサーは、ポーリングを使用して新しいイベントを監視します。

すべてがテストネット用に事前設定されていますが、他のネットワークで動作するように調整することも可能です。
ネットワークを変更するには、`.env`ファイルを作成し、`NETWORK=<mainnet|testnet|devnet|localnet>`という変数を設定します。

## インストール

1. 依存関係をインストールします。

```
pnpm install --ignore-workspace
```

2. データベースをセットアップします。

```
pnpm db:setup:dev
```

3. [コントラクトとデモデータを公開します](#demo-data)。

4. APIとインデクサーの両方を実行します。

```
pnpm dev
```

5. [http://localhost:3000/escrows](http://localhost:3000/escrows) または [http://localhost:3000/locked](http://localhost:3000/locked) にアクセスします。

## デモデータ<a name="demo-data"></a>

> CLIのアクティブなアドレスに十分なテストネット（または他のネット）のSUIがあることを確認してください。

以下のためのヘルパー関数がいくつかあります：

1. スマートコントラクトを公開する
2. デモデータを作成する（テストネット用）

デモデータを生成するには：

1. スマートコントラクトを公開します。

```
npx ts-node helpers/publish-contracts.ts
```

2. ロックされていないオブジェクトとロックされたオブジェクトのデモを生成します。

```
npx ts-node helpers/create-demo-data.ts
```

3. デモのエスクローを生成します。

```
npx ts-node helpers/create-demo-escrows.ts
```

データベースをリセットしたい場合（最初からやり直す場合）は、以下を実行します：

```
pnpm db:reset:dev && pnpm db:setup:dev
```

## API

APIは、イベントインデクサーから書き込まれたデータを公開します。

各リクエストには、1ページあたり最大50件のページネーションがあります。

| パラメータ | 想定される値    |
| ---------- | --------------- |
| limit      | number (1-50)   |
| cursor     | number          |
| sort       | 'asc' \| 'desc' |

利用可能なルートは2つあります：

### `/locked`: インデックス化されたロックオブジェクトを返します

利用可能なクエリパラメータ：

| パラメータ | 想定される値    |
| ---------- | ----------------- |
| deleted    | 'true' \| 'false' |
| keyId      | string            |
| creator    | string            |

### `/escrows`: インデックス化されたエスクローオブジェクトを返します

利用可能なクエリパラメータ：

| パラメータ | 想定される値    |
| ---------- | ----------------- |
| cancelled  | 'true' \| 'false' |
| swapped    | 'true' \| 'false' |
| recipient  | string            |
| sender     | string            |

> クエリ例：特定のアドレスのアクティブなエスクローのみを取得する（1ページあたり5件）
> `0xfe09cf0b3d77678b99250572624bf74fe3b12af915c5db95f0ed5d755612eb68`

```
curl --location 'http://localhost:3000/escrows?limit=5&recipient=0xfe09cf0b3d77678b99250572624bf74fe3b12af915c5db95f0ed5d755612eb68&cancelled=false&swapped=false'
```

## イベントインデクサー

> インデkサーは単一のインスタンスのみ実行してください。

インデクサーはポーリングを使用して新しいイベントを監視します。
カーソルデータをデータベースに保存しているため、APIを再起動したときに中断したところから再開できます。

インデクサーを個別に実行するには、以下を実行します：

```
pnpm indexer
```
