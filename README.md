# Raffle

A trustless, automated on-chain raffle (lottery) built with Solidity and Foundry.

Players enter by sending ETH. After a configurable interval, Chainlink Automation triggers winner selection. Chainlink VRF provides verifiable randomness to pick the winner, who receives the full prize pool.

## How It Works

1. Players call `enter()` with at least the entrance fee in ETH
2. Chainlink Automation monitors `checkUpkeep()` off-chain
3. Once the interval passes and conditions are met, Automation calls `performUpkeep()`
4. A VRF randomness request is sent to Chainlink
5. `fulfillRandomWords()` receives the random number, selects a winner, and transfers the prize

## Architecture

- `src/Raffle.sol` — Core raffle contract
- `script/DeployRaffle.s.sol` — Deployment script with automatic subscription setup
- `script/HelperConfig.s.sol` — Network-specific configuration (Sepolia, local Anvil)
- `script/Interactions.s.sol` — Scripts for subscription management

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

## Sepolia Deployment

| Parameter       | Value                                        |
|----------------|----------------------------------------------|
| VRF Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| LINK Token      | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |
| Gas Lane        | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| Entrance Fee    | 0.01 ETH                                     |
| Interval        | 30 seconds                                   |

## Security Considerations

- Randomness is provided by Chainlink VRF — not manipulable by miners or the contract owner
- No owner privileges after deployment — fully trustless
- Follows checks-effects-interactions pattern throughout
- Winner selection and prize transfer happen atomically in the VRF callback
