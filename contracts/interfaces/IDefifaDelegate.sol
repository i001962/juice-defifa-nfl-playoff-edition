// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJB721TieredGovernance.sol';
import 'lib/typeface/contracts/interfaces/ITypeface.sol';

import './../structs/DefifaTierRedemptionWeight.sol';

interface IDefifaDelegate is IJB721TieredGovernance {
  function TOTAL_REDEMPTION_WEIGHT() external returns (uint256);

  function typeface() external returns (ITypeface);

  function tierRedemptionWeights() external returns (uint256[128] memory);

  function setTierRedemptionWeights(DefifaTierRedemptionWeight[] memory _tierWeights) external;

  function initialize(
    uint256 _projectId,
    IJBDirectory _directory,
    string memory _name,
    string memory _symbol,
    IJBFundingCycleStore _fundingCycleStore,
    string memory _baseUri,
    IJBTokenUriResolver _tokenUriResolver,
    string memory _contractUri,
    JB721PricingParams memory _pricing,
    IJBTiered721DelegateStore _store,
    JBTiered721Flags memory _flags,
    ITypeface _typeface,
    string[] memory _tierNames
  ) external;
}
