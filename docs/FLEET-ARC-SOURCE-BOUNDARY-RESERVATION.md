# Fleet ARC — Repository / Source-Boundary Reservation

Status: **source-boundary reservation only — Fleet ARC not yet instantiated**  
Date: 2026-09-11  
Intended ARC ID: `fleet`  
Repository class: `ryz3n_owned_product_domain`

## Founder-directed repository decision

When Fleet ARC is actually instantiated, its authoritative ARC source belongs under:

`Javalin13/FleetConnect/arc/`

Fleet ARC will follow the same repository-ownership pattern as Cargo ARC inside CargoConnect because FleetConnect is a RYZ3N-owned product/domain with its own established authoritative repository.

This file **does not begin Fleet ARC construction**, create an ARC runtime, claim OMEGA registration, claim FACTORY activation, claim maturity or alter the existing FleetConnect product runtime.

## Boundaries when birth is authorized

- `Javalin13/FleetConnect` → Fleet product/domain truth + Fleet ARC-specific package under `arc/`;
- `Javalin13/ryzen-core` → universal RYZ3N/ARC canon, schemas and reusable standards only;
- `Javalin13/prime-vps-migration` → bounded PRIME/OMEGA/FACTORY supervision pointers only;
- isolated Fleet ARC runtime/secrets/state → outside Git under the established ARC runtime security model.

Do not create a separate standalone Fleet-ARC repository merely because Fleet ARC exists unless a later explicit source-boundary migration decision changes this canon.

## Canonical references

- `Javalin13/ryzen-core/12-arc-productization/ARC-REPOSITORY-OWNERSHIP-AND-SOURCE-BOUNDARY-STANDARD.md`
- `Javalin13/ryzen-core/12-arc-productization/OMEGA-ARC-FACTORY-STEWARDSHIP-STANDARD.md`
- `Javalin13/VONDA-Corporation/arc/GOLDEN-ARC-BLUEPRINT-OMEGA-FACTORY-AMENDMENT.md`

## No-Horizon invariant

There is no Horizon/Horizon Core orchestration tier. The canonical platform is **RYZ3N**.

> **When Fleet ARC is born, it lives with FleetConnect's domain truth.**
