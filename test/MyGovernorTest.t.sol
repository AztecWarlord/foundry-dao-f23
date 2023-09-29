// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    GovToken public govToken;
    TimeLock public timelock;
    MyGovernor public governor;
    Box public box;

    uint256 public constant MIN_DELAY = 3600; // 1 hour after voting passed
    uint256 public constant VOTING_PERIOD = 50400; // how many blocks till a vote is active
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a vote is active

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] public proposers;
    address[] public executors;

    bytes[] public calldatas;
    address[] public targets;
    uint256[] public values;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGoverenance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        targets.push(address(box));
        values.push(0);
        calldatas.push(encodedFunctionCall);

        // 1. propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 2. View the state
        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        // 3. Vote
        string memory reason = "cuz blue frog is cool";
        uint8 support = 1; // 1 = yes, 2 = no, 0 = abstain

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, support, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute the TX
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
