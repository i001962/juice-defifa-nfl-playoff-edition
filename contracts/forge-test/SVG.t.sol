// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'forge-std/Test.sol';
import '../DefifaDelegate.sol';

// import {CapsulesTypeface} from "../lib/capsules/contracts/CapsulesTypeface.sol";

contract EmptyTest is Test {
  DefifaDelegate _delegate = new DefifaDelegate();

  function setUp() public {}

  function testOutput() public {
    string memory returnedUri = _delegate.tokenURI(1);
    string[] memory inputs = new string[](3);
    inputs[0] = 'node';
    inputs[1] = './open.js';
    inputs[2] = returnedUri;
    bytes memory res = vm.ffi(inputs);
    res;
    // vm.ffi(inputs);
  }
}
