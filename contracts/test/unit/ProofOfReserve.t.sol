// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProofOfReserve} from "../../src/core/ProofOfReserve.sol";
import {IProofOfReserve} from "../../src/interfaces/IProofOfReserve.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";

contract ProofOfReserveTest is Test {
    ProofOfReserve public por;
    MockERC20 public token;
    MockOracle public oracle;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        token = new MockERC20("TSLA", "TSLA");
        oracle = new MockOracle(18, "TSLA PoR");

        vm.prank(owner);
        por = new ProofOfReserve(owner);

        // Set oracle to report reserves = total supply (fully backed)
        oracle.setPrice(int256(token.totalSupply()));
    }

    function test_registerFeed() public {
        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);
    }

    function test_verifyReserve_fullyBacked() public {
        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);
        assertTrue(por.verifyReserve(address(token)));
    }

    function test_verifyReserve_undercollateralized() public {
        // Mint more tokens than reserves
        token.mint(address(this), 1_000_000e18);

        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);
        assertFalse(por.verifyReserve(address(token)));
    }

    function test_getReserveRatio_100percent() public {
        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);
        uint256 ratio = por.getReserveRatio(address(token));
        assertEq(ratio, 1e18); // 100%
    }

    function test_revert_verifyReserve_staleData() public {
        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);

        // Warp past staleness
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert(abi.encodeWithSelector(IProofOfReserve.StaleData.selector, address(token), 2 hours));
        por.verifyReserve(address(token));
    }

    function test_revert_verifyReserve_feedNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IProofOfReserve.FeedNotRegistered.selector, address(token)));
        por.verifyReserve(address(token));
    }

    function test_removeFeed() public {
        vm.prank(owner);
        por.registerFeed(address(token), address(oracle), 1 hours);

        vm.prank(owner);
        por.removeFeed(address(token));

        vm.expectRevert(abi.encodeWithSelector(IProofOfReserve.FeedNotRegistered.selector, address(token)));
        por.verifyReserve(address(token));
    }

    function test_revert_registerFeed_unauthorized() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", makeAddr("attacker")));
        por.registerFeed(address(token), address(oracle), 1 hours);
    }
}