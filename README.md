# BondFy Smart Contracts

Solidity contracts for municipal bond issuance and managed bond purchases through the Bondfy digital platform.

## Contracts

### `BondFiMunicipalBonds`

ERC721A-based municipal bond NFT contract.

Key features:
- Municipality registry (`registerMunicipality`, `setMunicipalityActive`)
- Bond series creation by municipality treasury (`issueBondSeries`)
- Direct end-user purchases (`buyBonds`)
- Platform-routed purchases (`buyBondsFor`) for approved platform contracts
- Buyer classification (`setBuyerType`, `setBuyerTypeFor`)
- Platform fee accounting and withdrawal (`setPlatformFeeBps`, `withdrawPlatformFees`)

### `BondfyDigitalPlatform`

Platform operations contract that routes purchases into `BondfyMunicipalBonds`.

Key features:
- Owner/operator access model (`setOperator`)
- Investor profile and KYC flags (`upsertInvestor`)
- Managed purchases (`purchaseMunicipalBonds`)
- Optional native balance withdrawal (`withdrawNative`)

## Required Setup Sequence

1. Deploy `BondfyMunicipalBonds` with:
- `initialBondfyOperator`
- `initialOwner`

2. Deploy `BondfyDigitalPlatform` with:
- `initialOwner`
- deployed `BondfyMunicipalBonds` address

3. Authorize the platform contract in `BondfyMunicipalBonds`:
- `setApprovedPlatformContract(<BondfyDigitalPlatform>, true)`

4. Ensure `BondfyDigitalPlatform` can update buyer type metadata:
- Set `bondfyOperator` in `BondfyMunicipalBonds` to the platform contract address using `setBondfyOperator(...)`
  or
- Keep a trusted operator/owner account that calls `setBuyerTypeFor(...)` directly in the bond contract

5. Register municipalities and issue bond series:
- `registerMunicipality(...)`
- treasury calls `issueBondSeries(...)`

6. Onboard investors on platform:
- `setOperator(...)`
- operator calls `upsertInvestor(...)`

## Purchase Flows

### Direct User Purchase
- User calls `buyBonds(seriesId, quantity)` on `BondfyMunicipalBonds` with exact ETH (`priceWei * quantity`).

### Managed Platform Purchase
- Operator/owner calls `purchaseMunicipalBonds(investor, seriesId, quantity)` on `BondfyDigitalPlatform` with exact ETH.
- Platform forwards ETH to `buyBondsFor(...)` and mints NFTs directly to `investor`.

## Notes

- `maturityTimestamp` must be in the future when issuing a series.
- `platformFeeBps` is capped at `2000` (20%).
- `buyBonds` and `buyBondsFor` require exact payment value; over/underpayment reverts.
- Bond token IDs start at `1`.

## Source Files

- `contracts/BondfyMunicipalBonds.sol`
- `contracts/BondfyDigitalPlatform.sol`
