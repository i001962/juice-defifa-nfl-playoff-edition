// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol';
import '@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol';
import '../DefifaDeployer.sol';
import '../DefifaGovernor.sol';
import 'forge-std/Script.sol';

contract DeployMainnet is Script {
  // V3 mainnet controller.
  IJBController controller = IJBController(0xFFdD70C318915879d5192e8a0dcbFcB0285b3C98);
  // mainnet 721 store.
  IJBTiered721DelegateStore store =
    IJBTiered721DelegateStore(0xffB2Cd8519439A7ddcf2C933caedd938053067D2);
  // V3 goerli Payment terminal.
  IJBPaymentTerminal terminal = IJBPaymentTerminal(0x594Cb208b5BB48db1bcbC9354d1694998864ec63);

  address _defifaBallcats = 0x11834239698c7336EF232C00a2A9926d3375DF9D;
  // Game params.
  uint48 _start = 1683731800; // Sat Jan 14 2023 16:30:00 GMT-0500 (Eastern Standard Time)
  uint48 _mintDuration = 345600; // 4 days.
  uint48 _refundPeriodDuration = 14400; // 4 hours.
  uint48 _end = 1686264400; // Mon Feb 13 2023 04:00:00 GMT-0500 (Eastern Standard Time)
  uint80 _price = 0.07 ether;
  // We don't have to do this effenciently since this contract never gets deployed, its just used to build the broadcast txs
  string _name = 'Testing 910902';
  string _symbol = 'TEST';
  string _projectMetadataUri = 'Qmd6KVtevLjU6o9xTiJ2XcmhENvnMmgpEZGhgJZXCLtLVx';
  uint16 _reserved = 9; // 1 reserved NFT mintable to reserved beneficiary for every 9 NFTs minted outwardly. Inclusive, so 1 reserved can be minted as soon as the first token is minted outwardly.

  function run() external {
    vm.startBroadcast();
 
    JB721TierParams[] memory _tiers = new JB721TierParams[](14);

    for (uint256 _i; _i < 14; ) {
      _tiers[_i] = JB721TierParams({
        contributionFloor: _price,
        lockedUntil: 0,
        initialQuantity: 1_000_000_000 - 1, // max
        votingUnits: 1,
        reservedRate: _reserved,
        reservedTokenBeneficiary: _defifaBallcats,
        royaltyRate: 0,
        royaltyBeneficiary: address(0),
        encodedIPFSUri: '',
        allowManualMint: false,
        category: 1,
        shouldUseReservedTokenBeneficiaryAsDefault: true,
        shouldUseRoyaltyBeneficiaryAsDefault: false,
        transfersPausable: false
      });

      unchecked {
        ++_i;
      }
    }

    DefifaDelegateData memory _delegateData = DefifaDelegateData({
      name: _name,
      symbol: _symbol,
      baseUri: '',
      contractUri: '',
      tiers: _tiers,
      store: store,
      // Set owner will be set to the Governor later on in this script.
      owner: address(0)
    });

    DefifaLaunchProjectData memory _launchProjectData = DefifaLaunchProjectData({
      projectMetadata: JBProjectMetadata({content: _projectMetadataUri, domain: 0}),
      mintDuration: _mintDuration,
      start: _start,
      refundPeriodDuration: _refundPeriodDuration,
      end: _end,
      holdFees: false,
      splits: new JBSplit[](0),
      distributionLimit: 0,
      terminal: terminal
    });

    // Deploy the codeOrigin for the delegate
    DefifaDelegate _defifaDelegateCodeOrigin = new DefifaDelegate();

    // Deploy the deployer.
    DefifaDeployer defifaDeployer = new DefifaDeployer(
      address(_defifaDelegateCodeOrigin),
      controller,
      JBTokens.ETH,
      _defifaBallcats
    );

    // Set the owner as the governor (done here to easily count future nonces)
    _delegateData.owner = computeCreateAddress(tx.origin, vm.getNonce(tx.origin) + 1);

    // Launch the game - initialNonce
    uint256 _projectId = defifaDeployer.launchGameWith(_delegateData, _launchProjectData);
    // initialNonce + 1

    // Get a reference to the latest configured funding cycle's data source, which should be the delegate that was deployed and attached to the project.
    (, JBFundingCycleMetadata memory _metadata, ) = controller.latestConfiguredFundingCycleOf(
      _projectId
    );
    // initialNonce + 1 (view function)

    // Deploy the governor
    {
      address _governor = address(new DefifaGovernor(DefifaDelegate(_metadata.dataSource), _end));
      
      // These 3 should be the same:
      console.log(_delegateData.owner);
      console.log(_governor);
      console.log(Ownable(_metadata.dataSource).owner());
    }

    console.log(address(defifaDeployer));
    console.log(address(store));
    console.log(_metadata.dataSource);
  }
}

contract DeployGoerli is Script {
    // V3 goerli controller.
    IJBController controller = IJBController(0x7Cb86D43B665196BC719b6974D320bf674AFb395);
    // goerli 721 store.
    IJBTiered721DelegateStore store = IJBTiered721DelegateStore(
      0x3EA16DeFF07f031e86bd13C55961eB576cd579a6
    );
    // V3 goerli Payment terminal.
    IJBPaymentTerminal terminal = IJBPaymentTerminal(0x55d4dfb578daA4d60380995ffF7a706471d7c719);

  address _defifaBallcats = 0x11834239698c7336EF232C00a2A9926d3375DF9D;
  // Game params.
  uint48 _start = 1683731800; // Sat Jan 14 2023 16:30:00 GMT-0500 (Eastern Standard Time)
  uint48 _mintDuration = 345600; // 4 days.
  uint48 _refundPeriodDuration = 14400; // 4 hours.
  uint48 _end = 1686264400; // Mon Feb 13 2023 04:00:00 GMT-0500 (Eastern Standard Time)
  uint80 _price = 0.07 ether;
  // We don't have to do this effenciently since this contract never gets deployed, its just used to build the broadcast txs
  string _name = 'Testing 910902';
  string _symbol = 'TEST';
  string _projectMetadataUri = 'i';
  uint16 _reserved = 9; // 1 reserved NFT mintable to reserved beneficiary for every 9 NFTs minted outwardly. Inclusive, so 1 reserved can be minted as soon as the first token is minted outwardly.

  function run() external {
    vm.startBroadcast();
 
    JB721TierParams[] memory _tiers = new JB721TierParams[](14);

    for (uint256 _i; _i < 14; ) {
      _tiers[_i] = JB721TierParams({
        contributionFloor: _price,
        lockedUntil: 0,
        initialQuantity: 1_000_000_000 - 1, // max
        votingUnits: 1,
        reservedRate: _reserved,
        reservedTokenBeneficiary: _defifaBallcats,
        royaltyRate: 0,
        royaltyBeneficiary: address(0),
        encodedIPFSUri: '',
        allowManualMint: false,
        category: 1,
        shouldUseReservedTokenBeneficiaryAsDefault: true,
        shouldUseRoyaltyBeneficiaryAsDefault: false,
        transfersPausable: false
      });

      unchecked {
        ++_i;
      }
    }

    DefifaDelegateData memory _delegateData = DefifaDelegateData({
      name: _name,
      symbol: _symbol,
      baseUri: '',
      contractUri: '',
      tiers: _tiers,
      store: store,
      // Set owner will be set to the Governor later on in this script.
      owner: address(0)
    });

    DefifaLaunchProjectData memory _launchProjectData = DefifaLaunchProjectData({
      projectMetadata: JBProjectMetadata({content: _projectMetadataUri, domain: 0}),
      mintDuration: _mintDuration,
      start: _start,
      refundPeriodDuration: _refundPeriodDuration,
      end: _end,
      holdFees: false,
      splits: new JBSplit[](0),
      distributionLimit: 0,
      terminal: terminal
    });

    // Deploy the codeOrigin for the delegate
    DefifaDelegate _defifaDelegateCodeOrigin = new DefifaDelegate();

    // Deploy the deployer.
    DefifaDeployer defifaDeployer = new DefifaDeployer(
      address(_defifaDelegateCodeOrigin),
      controller,
      JBTokens.ETH,
      _defifaBallcats
    );

    // Set the owner as the governor (done here to easily count future nonces)
    _delegateData.owner = computeCreateAddress(tx.origin, vm.getNonce(tx.origin) + 1);

    // Launch the game - initialNonce
    uint256 _projectId = defifaDeployer.launchGameWith(_delegateData, _launchProjectData);
    // initialNonce + 1

    // Get a reference to the latest configured funding cycle's data source, which should be the delegate that was deployed and attached to the project.
    (, JBFundingCycleMetadata memory _metadata, ) = controller.latestConfiguredFundingCycleOf(
      _projectId
    );
    // initialNonce + 1 (view function)

    // Deploy the governor
    {
      address _governor = address(new DefifaGovernor(DefifaDelegate(_metadata.dataSource), _end));
      
      // These 3 should be the same:
      console.log(_delegateData.owner);
      console.log(_governor);
      console.log(Ownable(_metadata.dataSource).owner());
    }

    console.log(address(defifaDeployer));
    console.log(address(store));
    console.log(_metadata.dataSource);
  }
}
