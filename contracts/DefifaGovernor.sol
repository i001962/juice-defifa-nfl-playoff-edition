// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@paulrberg/contracts/math/PRBMath.sol';
import '@openzeppelin/contracts/governance/Governor.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorSettings.sol';
import '@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol';
import './interfaces/IDefifaGovernor.sol';
import './interfaces/IDefifaDeployer.sol';
import './DefifaDelegate.sol';

/**
  @title
  DefifaGovernor

  @notice
  Governs a Defifa game.

  @dev
  Adheres to -
  IDefifaGovernor: General interface for the generic controller methods in this contract that interacts with funding cycles and tokens according to the protocol's rules.
*/
contract DefifaGovernor is Governor, GovernorCountingSimple, GovernorSettings, IDefifaGovernor {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//
  error INCORRECT_TIER_ORDER();


  //*********************************************************************//
  // -------------------- private constant properties ------------------ //
  //*********************************************************************//

  /** 
    @notice
    The duration of one block. 
  */
  uint256 internal constant _BLOCKTIME_SECONDS = 12;

  //*********************************************************************//
  // ------------------------ public constants ------------------------- //
  //*********************************************************************//

  /** 
    @notice
    The max voting power each tier has if every token within the tier votes.
  */
  uint256 public constant override MAX_VOTING_POWER_TIER = 1_000_000_000;

  /** 
    @notice
    The Defifa delegate contract that this contract is Governing.
  */
  IDefifaDelegate public immutable override defifaDelegate;

  /** 
    @notice
    Voting start timestamp after which voting can begin.
  */
  uint256 public immutable votingStartTime;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**     
    @param _defifaDelegate The Defifa delegate contract that this contract is Governing.
    @param _defifaDeployer .
  */
  constructor(IDefifaDelegate _defifaDelegate, IDefifaDeployer _defifaDeployer)
    Governor('DefifaGovernor')
    GovernorSettings(
      1, /* 1 block */
      45818, /* 1 week */
      0
    )
  {
    defifaDelegate = _defifaDelegate;
    // voting can start 7 days before the end phase fc starts
    votingStartTime = _defifaDeployer.endOf(_defifaDelegate.projectId()) - 1 weeks;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
    @notice
    Submits a scorecard to be voted on.

    @param _tierWeights The weights of each tier in the scorecard.

    @return The proposal ID. 
  */
  function submitScorecards(DefifaTierRedemptionWeight[] calldata _tierWeights)
    external
    override
    returns (uint256)
  {
    // Build the calldata normalized such that the Governor contract accepts.
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas
    ) = _buildScorecardCalldata(_tierWeights);

    // Submit the proposal.
    return propose(_targets, _values, _calldatas, '');
  }

  /**
    @notice
    Ratifies a scorecard that has been approved.

    @param _tierWeights The weights of each tier in the approved scorecard.

    @return The proposal ID. 
  */
  function ratifyScorecard(DefifaTierRedemptionWeight[] calldata _tierWeights)
    external
    override
    returns (uint256)
  {
    // Build the calldata to the delegate
    (
      address[] memory _targets,
      uint256[] memory _values,
      bytes[] memory _calldatas
    ) = _buildScorecardCalldata(_tierWeights);

    // Attempt to execute the proposal.
    return execute(_targets, _values, _calldatas, keccak256(''));
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  /** 
    @notice
    Build the calldata normalized such that the Governor contract accepts. 

    @param _tierWeights The weights of each tier in the scorecard data.

    @return The targets to send transactions to.
    @return The values to send allongside the transactions.
    @return The calldata to send allongside the transactions.
  */
  function _buildScorecardCalldata(DefifaTierRedemptionWeight[] calldata _tierWeights)
    internal
    view
    returns (
      address[] memory,
      uint256[] memory,
      bytes[] memory
    )
  {
    // Set the one target to be the delegate's address.
    address[] memory _targets = new address[](1);
    _targets[0] = address(defifaDelegate);

    // There are no values sent.
    uint256[] memory _values = new uint256[](1);

    // Build the calldata from the tier weights.
    bytes memory _calldata = abi.encodeWithSelector(
      DefifaDelegate.setTierRedemptionWeights.selector,
      (_tierWeights)
    );

    // Add the calldata.
    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = _calldata;

    return (_targets, _values, _calldatas);
  }

  /** 
    @notice
    Gets an account's voting power given a number of tiers to look through.

    @param _account The account to get votes for.
    @param _blockNumber The block number to measure votes from.
    @param _params The params to decode tier ID's from.

    @return votingPower The amount of voting power.
  */
  function _getVotes(
    address _account,
    uint256 _blockNumber,
    bytes memory _params
  ) internal view virtual override(Governor) returns (uint256 votingPower) {
    // Decode the tier IDs from the provided param bytes.
    uint256[] memory _tierIds = abi.decode(_params, (uint256[]));

    // Keep a reference to the number of tiers.
    uint256 _numbeOfTiers = _tierIds.length;

    // Loop over all tiers gathering the voting share of the provided account.
    uint256 _prevTierId;

    // Keep a reference to the tier being iterated on.
    uint256 _tierId;

    for (uint256 _i; _i < _numbeOfTiers; ) {
      // Set the tier being iterated on.
      _tierId = _tierIds[_i];

      // Enforce the tiers to be in ascending order to make sure there aren't duplicate tier IDs in the params.
      if (_tierId <= _prevTierId) revert INCORRECT_TIER_ORDER();

      // Set the previous tier ID.
      _prevTierId = _tierId;

      // Keep a reference to the number of tier votes for the account.
      uint256 _tierVotesForAccount = defifaDelegate.getPastTierVotes(
        _account,
        _tierId,
        _blockNumber
      );

      // If there is tier voting power, increment the result by the proportion of votes the account has to the total, multiplied by the tier's maximum vote power.
      unchecked {
        if (_tierVotesForAccount != 0)
          votingPower += PRBMath.mulDiv(
            MAX_VOTING_POWER_TIER,
            _tierVotesForAccount,
            defifaDelegate.getPastTierTotalVotes(_tierId, _blockNumber)
          );
      }

      ++_i;
    }
  }

  /** 
    @notice
    By default, look for voting power within all tiers.

    @return votingPower The amount of voting power.
  */
  function _defaultParams() internal view virtual override returns (bytes memory) {
    // Get a reference to the number of tiers.
    uint256 _count = defifaDelegate.store().maxTierIdOf(address(defifaDelegate));

    // Initialize an array to store the IDs.
    uint256[] memory _ids = new uint256[](_count);

    // Add all tiers to the array.
    for (uint256 _i; _i < _count; ) {
      // Tiers start counting from 1.
      _ids[_i] = _i + 1;

      unchecked {
        ++_i;
      }
    }

    // Return the encoded IDs.
    return abi.encode(_ids);
  }

  function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
    // calculating the voting delay based on the votingStartTime configured in the constructor
    if (votingStartTime > block.timestamp) {
      return (votingStartTime - block.timestamp) / _BLOCKTIME_SECONDS;
    }
    // no voting delay once voting is active
    return 0;
  }

  // Required override.
  function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
    return super.votingPeriod();
  }

  // Required override.
  function quorum(uint256 blockNumber) public pure override(IGovernor) returns (uint256) {
    blockNumber;
    // TODO: I just picked some random value for now, decide what a appropriate quorum should be
    return 2 * MAX_VOTING_POWER_TIER;
  }

  // Required override.
  function state(uint256 proposalId) public view override(Governor) returns (ProposalState) {
    return super.state(proposalId);
  }

  // Required override.
  function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) public override(Governor) returns (uint256) {
    return super.propose(targets, values, calldatas, description);
  }

  // Required override.
  function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
    return super.proposalThreshold();
  }

  // Required override.
  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor) {
    super._execute(proposalId, targets, values, calldatas, descriptionHash);
  }

  // Required override.
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor) returns (uint256) {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  // Required override.
  function _executor() internal view override(Governor) returns (address) {
    return super._executor();
  }

  function supportsInterface(bytes4 interfaceId) public view override(Governor) returns (bool) {
    return super.supportsInterface(interfaceId);
  }
}
