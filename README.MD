# Dapp — StarkNet Crowdfunding Registry

A small Cairo (StarkNet) contract project that implements a crowdfunding/registry pattern: create campaigns, contribute funds, check campaign goal/progress, and allow campaign creators to withdraw raised funds. Built with Cairo 1.0, ScarB, and Starknet Foundry (snforge).

## What's included

- `src/lib.cairo` — the main contract source (campaign creation, pay, query goal/progress, withdraw).
- `Scarb.toml` — ScarB project manifest and `test` script (`snforge test`).
- `tests/` — place for contract tests (if present).

## Quick start / prerequisites

You need Rust/Cargo and the ScarB + Starknet Foundry toolchain.

Install ScarB (Cairo package manager):

```fish
# install scarb with cargo
cargo install --locked scarb
```

Install Starknet Foundry (`snforge`) following the official instructions for your platform. If you have `snforge` available on PATH you can call it directly; otherwise install the prebuilt or via cargo as documented by Foundry.

Verify installations:

```fish
scarb --version
snforge --help
```

## Build

Compile the Cairo project (generates artifacts under `target/`):

```fish
scarb build
```

If you encounter a panic from the storage plugin ("Invalid storage interface type"), see Troubleshooting below — usually caused by incorrect `#[storage]` usage or using event types inside storage.

## Test

Run tests (Scarb runs `snforge test` as configured in `Scarb.toml`):

```fish
scarb run test
# or directly
snforge test
```

## Common commands (fish shell)

- Build: `scarb build`
- Run tests: `scarb run test` or `snforge test`
- Build release: `scarb build --release`

## Notes about the contract / storage

During development you may see two common storage styles in Cairo code:

- array/vector-style storage (fields like `titles`, `goal_amount`, `raised_amount`, using `.push()` and `.at(i).read()`), and
- map-style storage (a `map<u64, CampaignData>` keyed by campaign id).

The project must use one consistent storage model. If the `#[storage]` struct references types that are not valid storage node types (for example event structs or types with conflicting derives), the Cairo StarkNet plugin may panic with `Invalid storage interface type`.

If you edit `src/lib.cairo`, ensure:

- `#[storage]` is applied only once, on the `Storage` struct.
- Storage member types are valid storage nodes (arrays, maps) or plain data structs (no `starknet::Event` derive).
- Event structs are separate from stored data types (avoid using the same name for both an event and a storage struct).

If you need help fixing a storage error, share the relevant `Storage` struct and the types it references and I can help adjust them.

## Withdrawals & token transfers

This contract keeps accounting for "raised_amount" per campaign. To actually transfer tokens (ERC20-like token, ETH/STRK contracts on StarkNet), the contract must call the token contract's `transfer` function. Typical safe pattern:

1. Check caller is campaign creator.
2. Check campaign has non-zero balance.
3. Effects: zero the stored raised amount.
4. Interaction: call token contract to transfer amount to creator.

Note: token transfer code depends on the token contract interface. The project currently emits a `Withdrawn` event and updates storage; add a token transfer call when you have the token interface available.

## Troubleshooting

- Storage plugin panic: re-check `#[storage]` placement and that storage member types are plain data or supported storage nodes.
- LSP / VS Code "Request textDocument/semanticTokens/full failed. Source: Cairo 1.0": often caused by language-server crashes when parsing invalid/incomplete code. Fixing syntax/storage issues in `src/lib.cairo` usually resolves this.
- If `scarb build` shows ambiguous method calls (e.g. ambiguous `.at()` or missing `.push()`): check that the storage member is declared with the correct node type (`array<T>` for `.push`/`.len`, `map<K,V>` for `.at(...).read()` semantics) and import the right storage traits if necessary.

