// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";
import {ComplianceRegistry} from "../../src/core/ComplianceRegistry.sol";
import {ProofOfReserve} from "../../src/core/ProofOfReserve.sol";
import {CircuitBreaker} from "../../src/core/CircuitBreaker.sol";
import {SafetyVault} from "../../src/core/SafetyVault.sol";

/// @title VaultHandler — Drives deposit/withdraw/drain/rescue actions for invariant testing.
contract VaultHandler is Test {
    SafetyVault public vault;
    MockERC20 public token;
    CircuitBreaker public breaker;
    address public owner;

    address[] public actors;
    mapping(address => bool) public isActor;

    uint256 public sumDeposited; // mirror: total tokens user-deposited via this handler
    uint256 public sumWithdrawn; // mirror: total tokens user-withdrew via this handler

    constructor(
        SafetyVault _vault,
        MockERC20 _token,
        CircuitBreaker _breaker,
        address _owner,
        address[] memory _actors
    ) {
        vault = _vault;
        token = _token;
        breaker = _breaker;
        owner = _owner;
        actors = _actors;
        for (uint256 i = 0; i < _actors.length; i++) {
            isActor[_actors[i]] = true;
        }
    }

    function _pickActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _pickActor(actorSeed);
        amount = bound(amount, 1, 1_000e18);

        if (vault.emergencyDrained(address(token))) return;
        if (breaker.isHalted(address(token))) return;
        if (token.balanceOf(actor) < amount) return;

        (, uint256 cap, uint256 totalDep) = vault.tokens(address(token));
        if (totalDep + amount > cap) return;

        vm.prank(actor);
        try vault.deposit(address(token), amount) {
            sumDeposited += amount;
        } catch {}
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _pickActor(actorSeed);
        amount = bound(amount, 1, 1_000e18);

        if (vault.emergencyDrained(address(token))) return;
        if (breaker.isHalted(address(token))) return;

        uint256 bal = vault.balances(address(token), actor);
        if (bal < amount) return;

        vm.prank(actor);
        try vault.withdraw(address(token), amount) {
            sumWithdrawn += amount;
        } catch {}
    }

    function rescueExcess(uint256 amount) external {
        amount = bound(amount, 1, 100e18);
        uint256 balance = token.balanceOf(address(vault));
        (,, uint256 totalDep) = vault.tokens(address(token));
        uint256 excess = balance > totalDep ? balance - totalDep : 0;
        if (amount > excess) return;

        vm.prank(owner);
        try vault.rescueExcessTokens(address(token), owner, amount) {} catch {}
    }
}

/// @title SafetyVaultInvariant — Sanity-checks vault accounting under random sequences of actions.
contract SafetyVaultInvariantTest is StdInvariant, Test {
    SafetyVault public vault;
    MockERC20 public token;
    MockOracle public porOracle;
    MockOracle public priceOracle;
    ComplianceRegistry public compliance;
    ProofOfReserve public por;
    CircuitBreaker public breaker;
    VaultHandler public handler;

    address public owner;
    address[] public actors;

    uint256 constant INITIAL_RESERVES = 10_000_000e18;
    uint256 constant INITIAL_PRICE = 150_000_000_000;
    uint256 constant CAP = 100_000_000e18;

    function setUp() public {
        owner = makeAddr("owner");

        vm.startPrank(owner);
        token = new MockERC20("RWA", "RWA");
        porOracle = new MockOracle(18, "PoR");
        priceOracle = new MockOracle(8, "Price");
        porOracle.setPrice(int256(INITIAL_RESERVES));
        priceOracle.setPrice(int256(INITIAL_PRICE));

        compliance = new ComplianceRegistry(owner);
        por = new ProofOfReserve(owner);
        breaker = new CircuitBreaker(owner);
        vault = new SafetyVault(owner, address(compliance), address(por), address(breaker));

        por.registerFeed(address(token), address(porOracle), 1 hours);
        breaker.registerToken(address(token), address(priceOracle));
        vault.allowToken(address(token), CAP);

        // Build a small actor set, verify them all, fund them all.
        for (uint160 i = 1; i <= 5; i++) {
            address a = address(i + 0x1000);
            actors.push(a);
            compliance.verifyIdentity(a, 1, block.timestamp + 365 days);
            token.transfer(a, 100_000e18);
        }
        vm.stopPrank();

        // Each actor approves the vault.
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }

        handler = new VaultHandler(vault, token, breaker, owner, actors);
        targetContract(address(handler));
    }

    /// @dev INVARIANT: vault's accounted totalDeposited equals the sum of user balances.
    ///      This must hold even after rescueExcess (which never touches balances/totalDeposited)
    ///      and after emergencyDrain (which also leaves the accounting intact — drained tokens
    ///      become claims that must be honored off-chain).
    function invariant_sumBalancesEqualsTotalDeposited() public view {
        uint256 sumBalances;
        for (uint256 i = 0; i < actors.length; i++) {
            sumBalances += vault.balances(address(token), actors[i]);
        }
        (,, uint256 totalDeposited) = vault.tokens(address(token));
        assertEq(sumBalances, totalDeposited, "sum(balances) != totalDeposited");
    }

    /// @dev INVARIANT: while NOT drained, the vault must physically hold at least totalDeposited.
    ///      This guarantees every accounted balance is redeemable.
    function invariant_solvencyWhileLive() public view {
        if (vault.emergencyDrained(address(token))) return;
        (,, uint256 totalDeposited) = vault.tokens(address(token));
        assertGe(token.balanceOf(address(vault)), totalDeposited, "vault undercollateralized");
    }

    /// @dev INVARIANT: deposited - withdrawn matches the on-chain totalDeposited
    ///      (modulo nothing else — there's no fee, no minting, no fees in this layer).
    function invariant_handlerMirrorMatchesContract() public view {
        if (vault.emergencyDrained(address(token))) return;
        (,, uint256 totalDeposited) = vault.tokens(address(token));
        assertEq(totalDeposited, handler.sumDeposited() - handler.sumWithdrawn(), "mirror drift");
    }
}
