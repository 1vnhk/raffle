# Raffle

A trustless, automated on-chain raffle (lottery) built with Solidity and Foundry.

Players enter by sending ETH. After a configurable interval, Chainlink Automation triggers winner selection. Chainlink VRF provides verifiable randomness to pick the winner. Winners claim their prize via a pull-based withdrawal.

## Sepolia Deployment

**Verified contract**: [`0x878081d66cf5220b036A53804e9A034E02B3ea29`](https://sepolia.etherscan.io/address/0x878081d66cf5220b036A53804e9A034E02B3ea29)

The contract has been deployed, entered, and a winner was picked and claimed via Chainlink VRF and Automation on Sepolia testnet.

| Parameter       | Value                                        |
|----------------|----------------------------------------------|
| VRF Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| LINK Token      | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |
| Gas Lane        | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| Entrance Fee    | 0.01 ETH                                     |
| Interval        | 30 seconds                                   |
| Callback Gas Limit | 100,000                                   |

## How It Works

1. Players call `enter()` with exactly the entrance fee in ETH
2. Chainlink Automation monitors `checkUpkeep()` off-chain
3. Once the interval passes and conditions are met, Automation calls `performUpkeep()`
4. A VRF randomness request is sent to Chainlink
5. `fulfillRandomWords()` receives the random number, selects a winner, and credits the prize
6. The winner calls `claimPrize()` to withdraw their winnings

## Architecture

- `src/Raffle.sol` — Core raffle contract
- `script/DeployRaffle.s.sol` — Deployment script with automatic subscription setup
- `script/HelperConfig.s.sol` — Network-specific configuration (Sepolia, local Anvil)
- `script/Interactions.s.sol` — Scripts for subscription management

## Design Decisions

### Round-based player storage

A naive implementation stores players in a dynamic array and calls `delete s_players` in the VRF callback to reset for the next round. This is O(n) — the EVM must zero every storage slot in the array. With thousands of participants, this can exceed the VRF `callbackGasLimit`, permanently bricking the raffle.

This contract uses a **round-based architecture** instead:

```
mapping(uint256 round => mapping(uint256 index => address payable)) s_players;
mapping(uint256 round => uint256) s_playersCount;
uint256 s_currentRound;
```

Resetting between rounds is a single increment: `s_currentRound++`. O(1) regardless of player count. Old round data remains in storage but is inaccessible through the current round's getters. The VRF callback gas cost is constant and predictable.

### Pull pattern for prize withdrawal

Instead of pushing ETH to the winner inside the VRF callback, the prize is credited to a `s_pendingPrizes` mapping. The winner calls `claimPrize()` to withdraw.

This prevents two failure modes:
- **DoS by reverting receiver**: If the winner is a contract that reverts on ETH receipt, the push pattern would cause the entire VRF callback to fail, locking the raffle. With pull, the callback always succeeds — the reverting contract simply can't claim its prize, but the raffle continues.
- **Callback gas exhaustion**: The ETH transfer in a push pattern adds unpredictable gas cost (the receiver can run arbitrary code in `receive()`). Moving it out of the callback keeps `fulfillRandomWords` gas usage constant.

The tradeoff is UX: winners must send a second transaction to claim. In practice, this is standard in DeFi (vesting, airdrops, yield protocols all use pull patterns).

### Exact entrance fee

`enter()` requires `msg.value == i_entranceFee` (strict equality, not `>=`). This prevents users from accidentally overpaying and losing funds to the prize pool. Every entry contributes exactly the same amount, making the prize calculation deterministic: `prize = entranceFee * playersCount` (assuming no forced ETH via selfdestruct). 

**Duplicate entries from the same address are allowed** — each entry is an independent ticket that increases odds proportionally.

### Running prize pool counter

The prize for each round is `address(this).balance - s_totalPendingPrizes` — the contract's ETH balance minus all unclaimed prizes owed to previous winners.

A naive approach would look up each past winner's pending balance, but that requires knowing *who* to look up and scales with the number of unclaimed winners. Instead, a single `s_totalPendingPrizes` counter is incremented when a prize is credited and decremented when a prize is claimed. This keeps the prize calculation O(1) and correct regardless of how many winners haven't claimed yet.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/)

## Setup

```bash
git clone <repo>
cd raffle
make install
make setup
```

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

Required env variables:

```
SEPOLIA_RPC_URL=
ETHERSCAN_API_KEY=
SEPOLIA_ACCOUNT=
```

Import your deployer wallet into Foundry's encrypted keystore:

```bash
cast wallet import deployer --interactive
```

## Usage

### Run tests (local)

```bash
make test-unit
```

### Run tests against Sepolia fork

```bash
make test-sepolia
```

### Coverage report

```bash
make coverage
```

### Deploy locally (Anvil)

```bash
anvil
make deploy
```

### Deploy to Sepolia

> Before deploying, create and fund a VRF subscription at [vrf.chain.link](https://vrf.chain.link) and set the subscription ID in `HelperConfig.s.sol`.

```bash
make deploy ARGS="--network sepolia"
```

## Future Improvements

- **Invariant (stateful fuzz) testing**: The core solvency property `address(raffle).balance >= s_totalPendingPrizes` should hold after any sequence of `enter`, `performUpkeep`, `fulfillRandomWords`, and `claimPrize` calls. A stateful fuzz test with a handler contract would prove this under adversarial conditions, providing stronger guarantees than unit tests alone.

## Security Considerations

- Randomness is provided by Chainlink VRF — not manipulable by miners or the contract owner
- No owner privileges after deployment — fully trustless
- Round-based architecture ensures O(1) gas cost in VRF callback regardless of player count
- Pull pattern prevents DoS by reverting winners
- Running `s_totalPendingPrizes` counter ensures prize calculation is always solvent, even with multiple unclaimed winners across rounds
- Follows checks-effects-interactions pattern throughout
