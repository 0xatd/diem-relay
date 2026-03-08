// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {csDIEM} from "../src/csDIEM.sol";

/**
 * @title DeployCSDiem
 * @notice Deploys csDIEM to Base.
 *
 * Usage:
 *   DIEM=0xf4d97f2da56e8c3098f3a8d538db630a2606a024 \
 *   OPERATOR=0x... \
 *   forge script script/DeployCSDiem.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
 *
 * Env:
 *   DIEM       — DIEM token address (has built-in staking)
 *   ADMIN      — Admin address (defaults to deployer)
 *   OPERATOR   — Operator address (manages Venice forward-staking + DIEM donations)
 *   PRIVATE_KEY — Deployer private key
 */
contract DeployCSDiem is Script {
    function run() external {
        address diem = vm.envOr("DIEM", address(0xF4d97F2da56e8c3098f3a8D538DB630A2606a024));
        address admin = vm.envOr("ADMIN", msg.sender);
        address operator = vm.envAddress("OPERATOR");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        console.log("Deploying csDIEM...");
        console.log("  diem:    ", diem);
        console.log("  admin:   ", admin);
        console.log("  operator:", operator);

        vm.startBroadcast(deployerKey);

        csDIEM vault = new csDIEM(IERC20(diem), admin, operator);

        vm.stopBroadcast();

        console.log("");
        console.log("  csDIEM deployed at:", address(vault));
        console.log("  decimals:          ", vault.decimals());
        console.log("  decimalsOffset:     6 (virtual shares for inflation protection)");
        console.log("");
        console.log("  Post-deploy checklist:");
        console.log("  1. Operator: call deployToVenice() to forward-stake buffer excess");
        console.log("  2. Operator: call donate(amount) with DIEM to add yield");
        console.log("  3. Verify on Basescan");
    }
}
