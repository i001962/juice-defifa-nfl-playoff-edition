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
  uint48 _start = 1673731800; // Sat Jan 14 2023 16:30:00 GMT-0500 (Eastern Standard Time)
  uint48 _mintDuration = 345600; // 4 days.
  uint48 _refundPeriodDuration = 43200; // 12 hours.
  uint48 _end = 1676264400; // Mon Feb 13 2023 04:00:00 GMT-0500 (Eastern Standard Time)
  uint80 _price = 0.07 ether;
  // We don't have to do this effenciently since this contract never gets deployed, its just used to build the broadcast txs
  string _name = 'Defifa: American Football Playoffs 2023';
  string _symbol = 'DEFIFA 01';
  string _contractUri = 'QmWr59JLBDESicC7DpWukkf6Vdr3NCYfVij4K8qoJv66mv';
  string _projectMetadataUri = 'Qmd6KVtevLjU6o9xTiJ2XcmhENvnMmgpEZGhgJZXCLtLVx';
  uint16 _reserved = 9; // 1 reserved NFT mintable to reserved beneficiary for every 9 NFTs minted outwardly. Inclusive, so 1 reserved can be minted as soon as the first token is minted outwardly.

  function run() external {
    vm.startBroadcast();
 
    JB721TierParams[] memory _tiers = new JB721TierParams[](14);

    bytes32[] memory _teamEncodedIPFSUris = new bytes32[](14);
    _teamEncodedIPFSUris[0] = 0x8cfc0a1fea9a77c9e9480fcb01e13a13119061b56a9dd5fc04ad4d445d4535ad;
    _teamEncodedIPFSUris[1] = 0x4d809cfda23217090e10da217a2345fce13aefdd3a2af339ae135616bef00c24;
    _teamEncodedIPFSUris[2] = 0x30c64aad813af1756c99076e65c594714d75cc2a57208ff5e86e411ecc9c125c;
    _teamEncodedIPFSUris[3] = 0x168a6513fd85ce9c612e7b78591a2ba9569dea73b11cb63730107d1f2b6db615;
    _teamEncodedIPFSUris[4] = 0x18aa6d766db05b96a448cb58cff79bb7c634ac251e650128cfebb6495af2ce19;
    _teamEncodedIPFSUris[5] = 0xfafbfc3691f45a4e69b6bca740ff1984785657b7beb352415211b23bdd19486a;
    _teamEncodedIPFSUris[6] = 0x482f3c33e6585f91b8d04ec052c6d514688d0f9ccd11595cdaf5eb820ff8432a;
    _teamEncodedIPFSUris[7] = 0x64e73a62f5fef69c41cc60b1330f9c81b8d98ac2e964e7898a815d88c7e93e3c;
    _teamEncodedIPFSUris[8] = 0x60327d1125fdffa5ef25559f57d0dca9612b22fcadb5a780817cd87e22579181;
    _teamEncodedIPFSUris[9] = 0x98120e87584bcfbf0c6f82e09be8e1ac9b4e7256d4417889637e80d7f388105b;
    _teamEncodedIPFSUris[10] = 0x1f4c5d73015856a4695e3d0075e8decb13c0bc167f3d2d5f2158aded119b438e;
    _teamEncodedIPFSUris[11] = 0x8b6b21d5ddfbe2e959970c4ffb383ffd056d2977d6e6c051b07f39c6c28aeec5;
    _teamEncodedIPFSUris[12] = 0xe0913f3ba3713184ae2796bfd0162b8970a3d3fb6952ca9c45da4f24ec4e36d0;
    _teamEncodedIPFSUris[13] = 0xa89a7cbf0049d1d342d9bc9d40f02064397c29fea78165cf07fcf340b36a84df;

    for (uint256 _i; _i < 14; ) {
      _tiers[_i] = JB721TierParams({
        contributionFloor: _price,
        lockedUntil: 0,
        initialQuantity: 1_000_000_000 - 1, // max
        votingUnits: 1,
        reservedRate: _reserved,
        reservedTokenBeneficiary: _defifaBallcats,
        encodedIPFSUri: _teamEncodedIPFSUris[_i],
        allowManualMint: false,
        shouldUseBeneficiaryAsDefault: true,
        transfersPausable: true
      });

      unchecked {
        ++_i;
      }
    }

    DefifaDelegateData memory _delegateData = DefifaDelegateData({
      name: _name,
      symbol: _symbol,
      baseUri: 'ipfs://',
      contractUri: _contractUri,
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
  uint48 _start = 1673731800; // Sat Jan 14 2023 16:30:00 GMT-0500 (Eastern Standard Time)
  uint48 _mintDuration = 376084; //345600; // 4 days.
  uint48 _refundPeriodDuration = 43200; // 12 hours.
  uint48 _end = 1676264400; // Mon Feb 13 2023 04:00:00 GMT-0500 (Eastern Standard Time)
  uint80 _price = 0.07 ether;
  // We don't have to do this effenciently since this contract never gets deployed, its just used to build the broadcast txs
  string _name = 'Defifa: American Football Playoffs 2023';
  string _symbol = 'DEFIFA 01';
  string _contractUri = 'QmWr59JLBDESicC7DpWukkf6Vdr3NCYfVij4K8qoJv66mv';
  string _projectMetadataUri = 'Qmd6KVtevLjU6o9xTiJ2XcmhENvnMmgpEZGhgJZXCLtLVx';
  uint16 _reserved = 9; // 1 reserved NFT mintable to reserved beneficiary for every 9 NFTs minted outwardly. Inclusive, so 1 reserved can be minted as soon as the first token is minted outwardly.

  function run() external {
    vm.startBroadcast();
 
    JB721TierParams[] memory _tiers = new JB721TierParams[](14);

    bytes32[] memory _teamEncodedIPFSUris = new bytes32[](14);
    _teamEncodedIPFSUris[0] = 0x8cfc0a1fea9a77c9e9480fcb01e13a13119061b56a9dd5fc04ad4d445d4535ad;
    _teamEncodedIPFSUris[1] = 0x4d809cfda23217090e10da217a2345fce13aefdd3a2af339ae135616bef00c24;
    _teamEncodedIPFSUris[2] = 0x30c64aad813af1756c99076e65c594714d75cc2a57208ff5e86e411ecc9c125c;
    _teamEncodedIPFSUris[3] = 0x168a6513fd85ce9c612e7b78591a2ba9569dea73b11cb63730107d1f2b6db615;
    _teamEncodedIPFSUris[4] = 0x18aa6d766db05b96a448cb58cff79bb7c634ac251e650128cfebb6495af2ce19;
    _teamEncodedIPFSUris[5] = 0xfafbfc3691f45a4e69b6bca740ff1984785657b7beb352415211b23bdd19486a;
    _teamEncodedIPFSUris[6] = 0x482f3c33e6585f91b8d04ec052c6d514688d0f9ccd11595cdaf5eb820ff8432a;
    _teamEncodedIPFSUris[7] = 0x64e73a62f5fef69c41cc60b1330f9c81b8d98ac2e964e7898a815d88c7e93e3c;
    _teamEncodedIPFSUris[8] = 0x60327d1125fdffa5ef25559f57d0dca9612b22fcadb5a780817cd87e22579181;
    _teamEncodedIPFSUris[9] = 0x98120e87584bcfbf0c6f82e09be8e1ac9b4e7256d4417889637e80d7f388105b;
    _teamEncodedIPFSUris[10] = 0x1f4c5d73015856a4695e3d0075e8decb13c0bc167f3d2d5f2158aded119b438e;
    _teamEncodedIPFSUris[11] = 0x8b6b21d5ddfbe2e959970c4ffb383ffd056d2977d6e6c051b07f39c6c28aeec5;
    _teamEncodedIPFSUris[12] = 0xe0913f3ba3713184ae2796bfd0162b8970a3d3fb6952ca9c45da4f24ec4e36d0;
    _teamEncodedIPFSUris[13] = 0xa89a7cbf0049d1d342d9bc9d40f02064397c29fea78165cf07fcf340b36a84df;

    for (uint256 _i; _i < 14; ) {
      _tiers[_i] = JB721TierParams({
        contributionFloor: _price,
        lockedUntil: 0,
        initialQuantity: 1_000_000_000 - 1, // max
        votingUnits: 1,
        reservedRate: _reserved,
        reservedTokenBeneficiary: _defifaBallcats,
        encodedIPFSUri: _teamEncodedIPFSUris[_i],
        allowManualMint: false,
        shouldUseBeneficiaryAsDefault: true,
        transfersPausable: true
      });

      unchecked {
        ++_i;
      }
    }

    DefifaDelegateData memory _delegateData = DefifaDelegateData({
      name: _name,
      symbol: _symbol,
      baseUri: 'ipfs://',
      contractUri: _contractUri,
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
