// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernanceTimelock} from "../../src/core/GovernanceTimelock.sol";
import {IGovernanceTimelock} from "../../src/interfaces/IGovernanceTimelock.sol";

contract GovernanceTimelockTest is Test {
    GovernanceTimelock public timelock;
    address public owner;
    address public target;
    uint256 constant DELAY = 1 days;

    function setUp() public {
        owner = makeAddr("owner");
        target = makeAddr("target");
        vm.prank(owner);
        timelock = new GovernanceTimelock(owner, DELAY);
    }

    function test_initialState() public view {
        assertEq(timelock.minDelay(), DELAY);
    }

    function test_scheduleAndExecute() public {
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Schedule with default delay (0 means use minDelay)
        vm.prank(owner);
        timelock.schedule(target, data, 0);

        // Warp past the delay
        vm.warp(block.timestamp + DELAY + 1);

        // Execute
        vm.prank(owner);
        timelock.execute(target, data);
    }

    function test_revert_execute_beforeTime() public {
        bytes memory data = "";

        vm.prank(owner);
        timelock.schedule(target, data, 0);

        // Don't warp — should revert with OperationNotReady
        vm.prank(owner);
        vm.expectRevert();
        timelock.execute(target, data);
    }

    function test_revert_execute_beforeTime_proper() public {
        bytes memory data = "";

        vm.prank(owner);
        bytes32 opId = timelock.schedule(target, data, 0);

        // Don't warp — should revert with OperationNotReady
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceTimelock.OperationNotReady.selector, opId));
        timelock.execute(target, data);
    }

    function test_cancel() public {
        bytes memory data = "";

        vm.prank(owner);
        timelock.schedule(target, data, 0);

        vm.prank(owner);
        timelock.cancel(target, data);
    }

    function test_revert_schedule_unauthorized() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        timelock.schedule(target, "", 0);
    }

    function test_revert_schedule_tooSoon() public {
        vm.prank(owner);
        vm.expectRevert("GovernanceTimelock: delay below minimum");
        timelock.schedule(target, "", DELAY - 1);
    }

    function test_updateDelay() public {
        vm.prank(owner);
        timelock.updateDelay(2 days);
        assertEq(timelock.minDelay(), 2 days);
    }

    function test_revert_doubleSchedule() public {
        bytes memory data = "";

        vm.prank(owner);
        timelock.schedule(target, data, 0);

        // Same operation again should revert
        vm.prank(owner);
        vm.expectRevert();
        timelock.schedule(target, data, 0);
    }

    function test_revert_execute_afterGracePeriod() public {
        bytes memory data = "";

        vm.prank(owner);
        bytes32 opId = timelock.schedule(target, data, 0);

        // Past delay + grace period → OperationExpired
        vm.warp(block.timestamp + DELAY + timelock.GRACE_PERIOD() + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IGovernanceTimelock.OperationExpired.selector, opId));
        timelock.execute(target, data);
    }

    function test_revert_execute_nonExistent() public {
        // No schedule call → operation NON_EXISTENT
        vm.prank(owner);
        vm.expectRevert();
        timelock.execute(target, "");
    }

    function test_revert_cancel_nonExistent() public {
        vm.prank(owner);
        vm.expectRevert();
        timelock.cancel(target, "");
    }

    function test_revert_cancel_unauthorized() public {
        bytes memory data = "";
        vm.prank(owner);
        timelock.schedule(target, data, 0);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        timelock.cancel(target, data);
    }

    function test_getState_transitions() public {
        bytes memory data = "";
        assertEq(uint256(timelock.getState(target, data)), uint256(IGovernanceTimelock.OperationState.NON_EXISTENT));

        vm.prank(owner);
        timelock.schedule(target, data, 0);
        assertEq(uint256(timelock.getState(target, data)), uint256(IGovernanceTimelock.OperationState.SCHEDULED));

        vm.prank(owner);
        timelock.cancel(target, data);
        assertEq(uint256(timelock.getState(target, data)), uint256(IGovernanceTimelock.OperationState.CANCELLED));
    }

    function test_revert_execute_afterCancel() public {
        bytes memory data = "";

        vm.prank(owner);
        timelock.schedule(target, data, 0);
        vm.prank(owner);
        timelock.cancel(target, data);

        vm.warp(block.timestamp + DELAY + 1);
        vm.prank(owner);
        vm.expectRevert(); // state is CANCELLED, modifier rejects
        timelock.execute(target, data);
    }

    function test_revert_constructor_delayAboveMax() public {
        uint256 tooLong = timelock.MAX_DELAY() + 1;
        vm.expectRevert("GovernanceTimelock: delay exceeds max");
        new GovernanceTimelock(owner, tooLong);
    }

    function test_revert_updateDelay_aboveMax() public {
        uint256 tooLong = timelock.MAX_DELAY() + 1;
        vm.prank(owner);
        vm.expectRevert("GovernanceTimelock: delay exceeds max");
        timelock.updateDelay(tooLong);
    }

    function test_revert_execute_targetReverts() public {
        // Schedule a call to an address with no code → call returns success=true with empty data
        // for EOAs, so to actually test the failure branch we target a contract that always reverts.
        RevertingTarget rt = new RevertingTarget();
        bytes memory data = abi.encodeWithSignature("doRevert()");

        vm.prank(owner);
        timelock.schedule(address(rt), data, 0);
        vm.warp(block.timestamp + DELAY + 1);

        vm.prank(owner);
        vm.expectRevert("GovernanceTimelock: execution failed");
        timelock.execute(address(rt), data);
    }
}

contract RevertingTarget {
    function doRevert() external pure {
        revert("nope");
    }
}
