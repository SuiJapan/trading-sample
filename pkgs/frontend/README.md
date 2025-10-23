# トレーディング e2e デモ - フロントエンド

このdAppは、基本的なReactクライアントdAppをセットアップする `@mysten/create-dapp` を使用して作成されました。

## 最初のステップ

フロントエンドを実行する前に、APIのセットアップ手順に従って[コントラクトを公開](../api/README.md)する（または公開済みのものを再利用する）ことをお勧めします。

### デモコントラクト

以下のパッケージは、テストネット上でデモ目的で公開され、使用されています。

`escrow-contract.json` ファイル用:

```json
{
  "packageId": "0xead655f291ed9e1f5cac3bc4b2cfcccec91502940c0ba4d846936268964524c9"
}
```

`demo-contract.json` ファイル用:

```json
{
  "packageId": "0x164183829178d7620595919907d35bd3800b4345152f793594af8b2ba252d58a"
}
```

### 定数

`constants.ts` ファイルで、パッケージアドレスやAPIエンドポイントなどを変更できます。

## dAppの起動

依存関係をインストールするには、以下を実行します。

```bash
pnpm install --ignore-workspace
```

dAppを開発モードで起動するには、以下を実行します。

```bash
pnpm dev
```

## ビルド

デプロイ用にアプリをビルドするには、以下を実行します。

```bash
pnpm build
```

