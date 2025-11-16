# Integration Testing

The integration suite exercises live Hedera services (consensus + mirror). It is disabled by default and only runs when the required environment variables are present.

## Prerequisites

Set the following variables to point at a funded Hedera testnet account and an NFT you control:

```bash
export HEDERA_NETWORK=testnet
export HEDERA_OPERATOR_ID=0.0.xxxx
export HEDERA_OPERATOR_KEY=302e02...  # private key matching the operator account

export ZELIX_INTEGRATION=1
export ZELIX_TEST_TOKEN_ID=0.0.6001
export ZELIX_TEST_TOKEN_SERIAL=42
```

`ZELIX_INTEGRATION` acts as the gate. If it is unset or empty the integration suite exits early with `SkipZigTest` so `zig build test` remains fast and offline-friendly.

## Running

```bash
zig build integration
```

The command reuses the standard `zig` test runner. Any failures are shown in the terminal output; successful runs exit quietly.

## Notes

- Only a small NFT lookup is performed today. As more network coverage is added you can extend `tests/integration` with additional files and import them from `root.zig`.
- The integration suite shares the regular SDK module, so new APIs become available automatically.
- Keep credentials out of your shell history by sourcing them from a `.env` file or secret manager when possible.
