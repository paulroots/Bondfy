# BondFi Smart Contracts

Solidity contracts for municipal bond issuance and managed bond purchases through the BondFi digital platform.

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

### `BondFiDigitalPlatform`

Platform operations contract that routes purchases into `BondFiMunicipalBonds`.

Key features:
- Owner/operator access model (`setOperator`)
- Investor profile and KYC flags (`upsertInvestor`)
- Managed purchases (`purchaseMunicipalBonds`)
- Optional native balance withdrawal (`withdrawNative`)

## Required Setup Sequence

1. Deploy `BondFiMunicipalBonds` with:
- `initialBlockfiOperator`
- `initialOwner`

2. Deploy `BondFiDigitalPlatform` with:
- `initialOwner`
- deployed `BondFiMunicipalBonds` address

3. Authorize the platform contract in `BondFiMunicipalBonds`:
- `setApprovedPlatformContract(<BondFiDigitalPlatform>, true)`

4. Ensure `BondFiDigitalPlatform` can update buyer type metadata:
- Set `blockfiOperator` in `BondFiMunicipalBonds` to the platform contract address using `setBlockfiOperator(...)`
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
- User calls `buyBonds(seriesId, quantity)` on `BondFiMunicipalBonds` with exact ETH (`priceWei * quantity`).

### Managed Platform Purchase
- Operator/owner calls `purchaseMunicipalBonds(investor, seriesId, quantity)` on `BondFiDigitalPlatform` with exact ETH.
- Platform forwards ETH to `buyBondsFor(...)` and mints NFTs directly to `investor`.

## Notes

- `maturityTimestamp` must be in the future when issuing a series.
- `platformFeeBps` is capped at `2000` (20%).
- `buyBonds` and `buyBondsFor` require exact payment value; over/underpayment reverts.
- Bond token IDs start at `1`.

## Source Files

- `contracts/BondFiMunicipalBonds.sol`
- `contracts/BondFiDigitalPlatform.sol`
