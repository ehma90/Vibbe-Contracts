# Vibbe Contracts

Solidity contracts for Vibbe's on-chain functionality on [HyperEVM](https://hyperliquid.gitbook.io/hyperliquid-docs) (Hyperliquid's EVM chain). Built with [Foundry](https://book.getfoundry.sh/).

This repo only holds contract source, tests, and the deploy script — it isn't a running service. A contract only needs to be deployed once (or once per chain); after that, `vibbe-frontend` and `vibbe-backend` talk to it directly over RPC using its address, independent of this repo. See [How this connects to the other repos](#how-this-connects-to-the-other-repos) below.

## Contracts

### [`BadgeNFT.sol`](src/BadgeNFT.sol)
ERC-721 achievement badges. **Soulbound** — mintable, but non-transferable once minted, so a badge always reflects something the holder actually did rather than something they bought.

### [`VBFToken.sol`](src/VBFToken.sol)
Standard, freely transferable ERC-20 (18 decimals). Used for the app's faucet drips and prediction-pool payouts.

Both contracts use OpenZeppelin's `AccessControl` with a single `MINTER_ROLE`:
- **`admin`** (holds `DEFAULT_ADMIN_ROLE`) can grant/revoke `MINTER_ROLE` — e.g. to rotate signers without redeploying.
- **`minter`** is the only address allowed to call `mint()`. In production this is `vibbe-backend`'s own signer address (its `HYPEREVM_SIGNER_PRIVATE_KEY`) — nobody can mint from outside the app.

## Current deployments

| Network | Chain ID | BadgeNFT | VBFToken |
|---|---|---|---|
| HyperEVM Testnet | 998 | [`0x4E308952F874f04fF53024065D5986Ce240C5e5a`](https://testnet.purrsec.com/address/0x4E308952F874f04fF53024065D5986Ce240C5e5a) | [`0x9a1e653a59BFF3ba50c5257AB2De6A1a01260FB3`](https://testnet.purrsec.com/address/0x9a1e653a59BFF3ba50c5257AB2De6A1a01260FB3) |
| HyperEVM Mainnet | 999 | not yet deployed | not yet deployed |

Mainnet is intentionally not deployed yet — that's gated behind a contract review and moving the deployer/minter keys off plain env vars onto a KMS/custody-backed signer.

## Dev workflow

```shell
forge build        # compile
forge test          # run the test suite (unit tests, no network needed)
forge fmt            # format
```

For anything that touches a real chain, prove it locally first — start a free local chain and deploy to it before ever touching testnet/mainnet:

```shell
anvil --chain-id 998   # match HyperEVM testnet's chain ID so viem's chain-ID check behaves realistically

# in another terminal:
DEPLOYER_PRIVATE_KEY=<anvil's printed key 0> \
CONTRACT_ADMIN_ADDRESS=<anvil's printed address 0> \
BACKEND_MINTER_ADDRESS=<anvil's printed address 1> \
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

### Real deployment

Copy `.env.example` to `.env` and fill in `DEPLOYER_PRIVATE_KEY`, `CONTRACT_ADMIN_ADDRESS`, and `BACKEND_MINTER_ADDRESS` (see comments in that file for what each is for — testnet keys only; never put a mainnet key with real funds in a plain `.env`). Then:

```shell
forge script script/Deploy.s.sol --rpc-url hyperevm_testnet --broadcast   # or hyperevm_mainnet, once ready
```

Both RPC aliases are defined in [`foundry.toml`](foundry.toml).

**Gotcha:** HyperEVM testnet's block gas limit is only **3,000,000** — much lower than Ethereum's ~30M. `forge script` pads its gas estimate by ~30% by default, which can make a deployment look like it exceeds the limit (and report a misleading "failed" error) even when the real, unpadded gas requirement fits. If a deploy reports failure, check whether it actually landed on-chain (`cast code <address> --rpc-url ...`) before assuming it didn't — and if you need to retry cleanly, `--gas-estimate-multiplier 100` removes the padding.

After deploying, take the two printed addresses and update this README's deployments table, plus the consuming repos (next section).

## How this connects to the other repos

Neither `vibbe-frontend` nor `vibbe-backend` depends on this repo at runtime or at build time — they talk to HyperEVM directly over RPC, using a contract's **address** and a hand-written **minimal ABI** (only the functions each app actually calls), not anything imported from here. Deploying is a one-time action, like a database migration; afterward, "wiring it up" just means dropping the two addresses into env vars:

- **`vibbe-backend`**: `BADGE_NFT_ADDRESS`, `VBF_TOKEN_ADDRESS`, plus `HYPEREVM_SIGNER_PRIVATE_KEY` (must be the same key as this repo's `BACKEND_MINTER_ADDRESS`) — see `src/lib/chain.ts` and `src/lib/abis.ts`.
- **`vibbe-frontend`**: `NEXT_PUBLIC_VBF_TOKEN_ADDRESS` — see `src/hooks/useOnChainVbfBalance.ts` and `src/lib/web3-abis.ts`.

If a contract's function signatures change, the ABIs in both consuming repos need updating to match — there's currently no automated sync between them and this repo.
