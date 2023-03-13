// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@jbx-protocol/juice-721-delegate/contracts/JB721TieredGovernance.sol';
import '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol';
import 'lib/base64/base64.sol';

import './interfaces/IDefifaDelegate.sol';
import './libraries/DefifaFontImporter.sol';

import {IScriptyBuilder, InlineScriptRequest, WrappedScriptRequest} from 'scripty.sol/contracts/scripty/IScriptyBuilder.sol';


import "solady/src/utils/LibString.sol";


/** 
  @title
  DefifaDelegate

  @notice
  Defifa specific 721 tiered delegate.

  @dev
  Adheres to -
  IDefifaDelegate: General interface for the methods in this contract that interact with the blockchain's state according to the protocol's rules.

  @dev
  Inherits from -
  JB721TieredGovernance: A generic tiered 721 delegate.
*/
contract DefifaDelegate is IDefifaDelegate, JB721TieredGovernance {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error GAME_ISNT_OVER_YET();
  error INVALID_TIER_ID();
  error INVALID_REDEMPTION_WEIGHTS();
  error NOTHING_TO_CLAIM();

 //*********************************************************************//
  // -------------------- Scripty.sol Kmac hacks ------------------ //
  //*********************************************************************//

  /** 
    @notice
    somebody that knows more than me should fix this
  */
  address private constant _SCRIPTY_STORAGE_ADDRESS = 0x096451F43800f207FC32B4FF86F286EdaF736eE3;
  address private constant _SCRIPTY_BUILDER_ADDRESS = 0x16b727a2Fc9322C724F4Bc562910c99a5edA5084;
  address private constant _ETHFS_FILESTORAGE_ADDRESS = 0xFc7453dA7bF4d0c739C1c53da57b3636dAb0e11e;
  uint256 public constant BUFFER_SIZE = 1000000;
  //*********************************************************************//
  // -------------------- private constant properties ------------------ //
  //*********************************************************************//

  /** 
    @notice
    The funding cycle number of the mint phase. 
  */
  uint256 private constant _MINT_GAME_PHASE = 1;

  /** 
    @notice
    The funding cycle number of the end game phase. 
  */
  uint256 private constant _END_GAME_PHASE = 4;

  //*********************************************************************//
  // --------------------- public constant properties ------------------ //
  //*********************************************************************//

  /** 
    @notice 
    The total weight that can be divided among tiers.
  */
  uint256 public constant override TOTAL_REDEMPTION_WEIGHT = 1_000_000_000;

  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//

  /** 
    @notice 
    The redemption weight for each tier.

    @dev
    Tiers are limited to ID 128
  */
  uint256[128] private _tierRedemptionWeights;

  /**
    @notice
    The amount that has been redeemed.
   */
  uint256 private _amountRedeemed;

  /**
    @notice
    The amount of tokens that have been redeemed from a tier, refunds are not counted
  */
  mapping(uint256 => uint256) private _redeemedFromTier;

  /**
    @notice
    The names of each tier.

    @dev _tierId The ID of the tier to get a name for.
  */
  mapping(uint256 => string) private _tierNameOf;

   /**
    @notice
    The mints of each tier.

    @dev _tierId The ID of the tier to get a mints for.
  */
  mapping(uint256 => uint256) private _tierMintsOf;

  /**
    @notice
    The mints of each tier.

    @dev _tierId The ID of the tier to get a mints for.
  */
  mapping(uint256 => uint256) private _phase;


  //*********************************************************************//
  // ------------------------- external views -------------------------- //
  //*********************************************************************//

  /** 
    @notice
    The redemption weight for each tier.

    @return The array of weights, indexed by tier.
  */
  function tierRedemptionWeights() external view override returns (uint256[128] memory) {
    return _tierRedemptionWeights;
  }

  /**
    @notice 
    Part of IJBFundingCycleDataSource, this function gets called when a project's token holders redeem.

    @param _data The Juicebox standard project redemption data.

    @return reclaimAmount The amount that should be reclaimed from the treasury.
    @return memo The memo that should be forwarded to the event.
    @return delegateAllocations The amount to send to delegates instead of adding to the beneficiary.
  */
  function redeemParams(JBRedeemParamsData calldata _data)
    public
    view
    override
    returns (
      uint256 reclaimAmount,
      string memory memo,
      JBRedemptionDelegateAllocation[] memory delegateAllocations
    )
  {
    // Make sure fungible project tokens aren't being redeemed too.
    if (_data.tokenCount > 0) revert UNEXPECTED_TOKEN_REDEEMED();

    // Check the 4 bytes interfaceId and handle the case where the metadata was not intended for this contract
    // Skip 32 bytes reserved for generic extension parameters.
    if (
      _data.metadata.length < 36 ||
      bytes4(_data.metadata[32:36]) != type(IJB721Delegate).interfaceId
    ) revert INVALID_REDEMPTION_METADATA();

    // Set the only delegate allocation to be a callback to this contract.
    delegateAllocations = new JBRedemptionDelegateAllocation[](1);
    delegateAllocations[0] = JBRedemptionDelegateAllocation(this, 0);

    // Decode the metadata
    (, , uint256[] memory _decodedTokenIds) = abi.decode(
      _data.metadata,
      (bytes32, bytes4, uint256[])
    );

    // If the game is in its minting phase, reclaim Amount is the same as it cost to mint.
    if (fundingCycleStore.currentOf(_data.projectId).number == _MINT_GAME_PHASE) {
      // Keep a reference to the number of tokens.
      uint256 _numberOfTokenIds = _decodedTokenIds.length;

      for (uint256 _i; _i < _numberOfTokenIds; ) {
        unchecked {
          reclaimAmount += store
            .tierOfTokenId(address(this), _decodedTokenIds[_i])
            .contributionFloor;

          _i++;
        }
      }

      return (reclaimAmount, _data.memo, delegateAllocations);
    }

    // Return the weighted overflow, and this contract as the delegate so that tokens can be deleted.
    return (
      PRBMath.mulDiv(
        _data.overflow + _amountRedeemed,
        redemptionWeightOf(_decodedTokenIds, _data),
        totalRedemptionWeight(_data)
      ),
      _data.memo,
      delegateAllocations
    );
  }

  /** 
    @notice
    The cumulative weight the given token IDs have in redemptions compared to the `_totalRedemptionWeight`. 

    @param _tokenIds The IDs of the tokens to get the cumulative redemption weight of.

    @return cumulativeWeight The weight.
  */
  function redemptionWeightOf(uint256[] memory _tokenIds, JBRedeemParamsData calldata)
    public
    view
    virtual
    override
    returns (uint256 cumulativeWeight)
  {
    // If the game is over, set the weight based on the scorecard results.
    // Keep a reference to the number of tokens being redeemed.
    uint256 _tokenCount = _tokenIds.length;

    for (uint256 _i; _i < _tokenCount; ) {
      // Keep a reference to the token's tier ID.
      uint256 _tierId = store.tierIdOfToken(_tokenIds[_i]);

      // Keep a reference to the tier.
      JB721Tier memory _tier = store.tier(address(this), _tierId);

      // Calculate what percentage of the tier redemption amount a single token counts for.
      cumulativeWeight +=
        // Tier's are 1 indexed and are stored 0 indexed.
        _tierRedemptionWeights[_tierId - 1] /
        (_tier.initialQuantity - _tier.remainingQuantity + _redeemedFromTier[_tierId]);

      unchecked {
        ++_i;
      }
    }

    // If there's nothing to claim, revert to prevent burning for nothing.
    if (cumulativeWeight == 0) revert NOTHING_TO_CLAIM();
  }

  /** 
    @notice
    The cumulative weight that all token IDs have in redemptions. 

    @return The total weight.
  */
  function totalRedemptionWeight(JBRedeemParamsData calldata)
    public
    view
    virtual
    override
    returns (uint256)
  {
    // Set the total weight as the total scorecard weight.
    return TOTAL_REDEMPTION_WEIGHT;
  }

  /** 
    @notice
    The time remaining in the current phase. 

    @return leftPaddedTimeLeftString
  */
  function getTimeLeft(JBFundingCycle memory _fundingCycle)
        internal
        view
        returns (string memory leftPaddedTimeLeftString)
    {
        // Time Left
        uint256 start = _fundingCycle.start; // Project's funding cycle start time
        uint256 duration = _fundingCycle.duration; // Project's current funding cycle duration
        uint256 timeLeft;
        string memory paddedTimeLeft;
        string memory countString;
        if (duration == 0) {
            paddedTimeLeft = string.concat("Not set"); // If the funding cycle has no duration, show infinite duration
        } else {
            timeLeft = start + duration - block.timestamp; // Project's current funding cycle time left
            if (timeLeft > 2 days) {
                //countString = (timeLeft / 1 days).toString();
                countString = LibString.toString(timeLeft / 1 days);
                paddedTimeLeft = string.concat(
                            " ",
                            unicode"",
                            " ",
                            countString,
                            " Days");
            } else if (timeLeft > 2 hours) {
                //countString = (timeLeft / 1 hours).toString(); // 12 bytes || 8 visual + countString
                countString = LibString.toString(timeLeft / 1 hours);
                paddedTimeLeft = string.concat(
                            unicode"",
                            " ",
                            countString,
                            unicode" ʜouʀs"
                        );
            } else if (timeLeft > 2 minutes) {
                //countString = (timeLeft / 1 minutes).toString();
                countString = LibString.toString(timeLeft / 1 minutes);
                paddedTimeLeft = string.concat(
                            unicode"",
                            ' ',
                            countString,
                            unicode" ᴍɪɴuᴛᴇs"
                    );
            } else {
                //countString = (timeLeft / 1 seconds).toString();
                countString = LibString.toString(timeLeft / 1 seconds);

                paddedTimeLeft = string.concat(
                            unicode"",
                            ' ',
                            countString,
                            unicode" sᴇcoɴᴅs"
                );
            }
        }
        return paddedTimeLeft;
    }
  
  
  /**
    @notice
    The metadata URI of the provided token ID.

    @dev
    Defer to the tokenUriResolver if set, otherwise, use the tokenUri set with the token's tier.

    @param _tokenId The ID of the token to get the tier URI for.

    @return The token URI corresponding with the tier or the tokenUriResolver URI.
  */
  function tokenURI(uint256 _tokenId) public view override returns (string memory) {
    // KMac scripty builder
      WrappedScriptRequest[] memory requests = new WrappedScriptRequest[](3);

      requests[0].name = "p5-v1.5.0.min.js.gz";
      requests[0].wrapType = 2; // <script type="text/javascript+gzip" src="data:text/javascript;base64,[script]"></script>
      requests[0].contractAddress = _ETHFS_FILESTORAGE_ADDRESS;

      requests[1].name = "gunzipScripts-0.0.1.js";
      requests[1].wrapType = 1; // <script src="data:text/javascript;base64,[script]"></script>
      requests[1].contractAddress = _ETHFS_FILESTORAGE_ADDRESS;
      
      // Set 'global' variables and add prior to script written in p5.js
      JB721Tier memory _tier = store.tierOfTokenId(address(this), _tokenId);
      string memory tierName = _tierNameOf[_tier.id];
      string memory phase = LibString.toString(_phase[_tier.id -1]);
      string memory prizePool = '??';
      string memory burnToClaim = LibString.toString(_tierRedemptionWeights[_tier.id - 1]);
      string memory totalMinted = LibString.toString(_tierMintsOf[_tier.id -1]);
      //uint256 totalMinted = tiered721DelegateStore.totalSupply(_nft); // Project's _nft address
  
      // Funding Cycle
      // FC#
        JBFundingCycle memory fundingCycle = fundingCycleStore.currentOf(
            projectId
        ); 
      bytes memory controllerScript = abi.encodePacked(
           'let tierName ="',
            tierName,
           '";',
            'let phase ="',
           phase,
           '";',
           'let prizePool ="',
            prizePool,
           '";',
            'let timeRemaining ="',
            getTimeLeft(fundingCycle),
           '";',
            'let totalMinted ="',
           totalMinted,
           '";',
            'let burnToClaim ="',
            burnToClaim,
           '";',
            'let font = "data:font/truetype;charset=utf-8;base64,',
            DefifaFontImporter.getSkinnyFontSource(),
            '";',
           // the p5js js code here
           // 'function setup() {createCanvas(400, 400);}function draw() {background(220);circle(20,20,40)}'
           //'let page,camLoc,buttLeft,buttRight,timer,btn,pages=[],numOfPages=2,movingRight=!1,movingLeft=!1,isPaused=!1,defifaBlue=[19,228,240],txt=[["Prize Pool ",defifaBlue],["24ETH ",defifaBlue],["",defifaBlue]],pageImg=[];function preload(){pageImg[0]=loadImage("https://gateway.pinata.cloud/ipfs/Qmb4obBzUofeZtcUxhEWUYCmhneZMzCrBQrNGnJnqKNyDq"),pageImg[1]=loadImage("https://ipfs.io/ipfs/QmTSBSHXJgnVg16pjxnH3CAqkL4QDtBwr6aSHkbvhZFmR3")}function setup(){createCanvas(400,400),camLoc=createVector(0,0);for(let t=0;t<numOfPages;t++)buttLeft=createButton("Artwork"),buttLeft.position(10,canvas.height/2-30),buttRight=createButton("Score Card"),buttRight.style("background-color",color(defifaBlue)),buttRight.position(canvas.width/2-90,canvas.height/2-30),pages[t]=new Page(canvas.width/2*t,0,t,pageImg[t],txt,0==t?buttLeft:buttRight);timer=canvas.width/2}function drawtext(t,i,e){for(var o=t,a=0;a<e.length;++a){var c=e[a],s=c[0],h=c[1],g=textWidth(s);fill(h),text(s,o,i),o+=g}}function draw(){background(220),buttRight.mousePressed(goRight),buttLeft.mousePressed(goLeft),slide(),push(),translate(camLoc.x,camLoc.y);for(let t=0;t<numOfPages;t++)pages[t].run();pop()}function goRight(){movingLeft||isPaused||(movingRight=!0)}function goLeft(){movingRight||isPaused||(movingLeft=!0)}function slide(){movingRight&&!movingLeft&&timer>=0&&(camLoc.x-=20,timer-=20),movingLeft&&!movingRight&&timer>=0&&(camLoc.x+=20,timer-=20),0==timer&&(movingRight=!1,movingLeft=!1,timer=canvas.width/2),-camLoc.x<0&&(camLoc.x=0),-camLoc.x>pages[pages.length-1].loc.x&&(timer=canvas.width/2,movingRight=!1,movingLeft=!1,camLoc.x=-pages[pages.length-1].loc.x)}function keyPressed(){87===keyCode?camLoc.y+=20:83===keyCode?camLoc.y-=20:65===keyCode?camLoc.x+=20:68===keyCode&&(camLoc.x-=20)}class Page{constructor(t,i,e,o,a,c){this.loc=createVector(t,i),this.w=canvas.width/2,this.h=canvas.height/2,this.pageNum=e+1,this.img=o}run(){image(this.img,this.loc.x,this.loc.y,400,400),textSize(20),textAlign(LEFT);2==this.pageNum&&drawtext(this.loc.x+112,this.loc.y+30,txt),line(this.loc.x,this.loc.y,this.loc.x+this.w,this.loc.y),line(this.loc.x,this.loc.y,this.loc.x,this.loc.y+this.h),line(this.loc.x,this.loc.y+this.h,this.loc.x+this.w,this.loc.y+this.h),line(this.loc.x+this.w,this.loc.y,this.loc.x+this.w,this.h)}}'
           //'let page,camLoc,buttLeft,buttRight,timer,btn,pages=[],numOfPages=2,movingRight=!1,movingLeft=!1,isPaused=!1,defifaBlue=[19,228,240],txt=[["Prize Pool ",defifaBlue],[prizePool,defifaBlue],["",defifaBlue]],pageImg=[];function preload(){pageImg[0]=loadImage("https://gateway.pinata.cloud/ipfs/Qmb4obBzUofeZtcUxhEWUYCmhneZMzCrBQrNGnJnqKNyDq"),pageImg[1]=loadImage("https://ipfs.io/ipfs/QmTSBSHXJgnVg16pjxnH3CAqkL4QDtBwr6aSHkbvhZFmR3")}function setup(){createCanvas(400,400),camLoc=createVector(0,0);for(let t=0;t<numOfPages;t++)buttLeft=createButton("Artwork"),buttLeft.position(10,canvas.height/2-30),buttRight=createButton("Score Card"),buttRight.style("background-color",color(defifaBlue)),buttRight.position(canvas.width/2-90,canvas.height/2-30),pages[t]=new Page(canvas.width/2*t,0,t,pageImg[t],txt,0==t?buttLeft:buttRight);timer=canvas.width/2}function drawtext(t,i,e){for(var o=t,a=0;a<e.length;++a){var c=e[a],s=c[0],h=c[1],g=textWidth(s);fill(h),text(s,o,i),o+=g}}function draw(){background(220),buttRight.mousePressed(goRight),buttLeft.mousePressed(goLeft),slide(),push(),translate(camLoc.x,camLoc.y);for(let t=0;t<numOfPages;t++)pages[t].run();pop()}function goRight(){movingLeft||isPaused||(movingRight=!0)}function goLeft(){movingRight||isPaused||(movingLeft=!0)}function slide(){movingRight&&!movingLeft&&timer>=0&&(camLoc.x-=20,timer-=20),movingLeft&&!movingRight&&timer>=0&&(camLoc.x+=20,timer-=20),0==timer&&(movingRight=!1,movingLeft=!1,timer=canvas.width/2),-camLoc.x<0&&(camLoc.x=0),-camLoc.x>pages[pages.length-1].loc.x&&(timer=canvas.width/2,movingRight=!1,movingLeft=!1,camLoc.x=-pages[pages.length-1].loc.x)}function keyPressed(){87===keyCode?camLoc.y+=20:83===keyCode?camLoc.y-=20:65===keyCode?camLoc.x+=20:68===keyCode&&(camLoc.x-=20)}class Page{constructor(t,i,e,o,a,c){this.loc=createVector(t,i),this.w=canvas.width/2,this.h=canvas.height/2,this.pageNum=e+1,this.img=o}run(){image(this.img,this.loc.x,this.loc.y,400,400),textSize(20),textAlign(LEFT);2==this.pageNum&&drawtext(this.loc.x+112,this.loc.y+30,txt),line(this.loc.x,this.loc.y,this.loc.x+this.w,this.loc.y),line(this.loc.x,this.loc.y,this.loc.x,this.loc.y+this.h),line(this.loc.x,this.loc.y+this.h,this.loc.x+this.w,this.loc.y+this.h),line(this.loc.x+this.w,this.loc.y,this.loc.x+this.w,this.h)}}'
           //'let page,camLoc,buttLeft,buttRight,timer,btn,pages=[],numOfPages=2,movingRight=!1,movingLeft=!1,isPaused=!1,defifaBlue=[19,228,240],txt1=[["Prize Pool: ",defifaBlue],[prizePool,defifaBlue],["",defifaBlue]],txt2=[["Phase: ",defifaBlue],[phase,defifaBlue],["",defifaBlue]],txt3=[["Time Remaining: ",defifaBlue],[timeRemaining,defifaBlue],["",defifaBlue]],txt4=[["Total Minted: ",defifaBlue],[totalMinted,defifaBlue],["",defifaBlue]],txt5=[["Burn to Claim: ",defifaBlue],[burnToClaim,defifaBlue],["",defifaBlue]],pageImg=[];function preload(){pageImg[0]=loadImage("https://gateway.pinata.cloud/ipfs/Qmb4obBzUofeZtcUxhEWUYCmhneZMzCrBQrNGnJnqKNyDq"),pageImg[1]=loadImage("https://ipfs.io/ipfs/QmTSBSHXJgnVg16pjxnH3CAqkL4QDtBwr6aSHkbvhZFmR3")}function setup(){myFont=loadFont(font),createCanvas(400,400),camLoc=createVector(0,0);for(let t=0;t<numOfPages;t++)buttLeft=createButton("Artwork"),buttLeft.position(10,canvas.height/2-30),buttRight=createButton("Score Card"),buttRight.style("background-color",color(defifaBlue)),buttRight.position(canvas.width/2-90,canvas.height/2-30),pages[t]=new Page(canvas.width/2*t,0,t,pageImg[t],txt1,0==t?buttLeft:buttRight);timer=canvas.width/2}function drawtext(t,e,i){for(var o=t,a=0;a<i.length;++a){var s=i[a],c=s[0],h=s[1],n=textWidth(c);fill(h),text(c,o,e),o+=n}}function draw(){background(220),buttRight.mousePressed(goRight),buttLeft.mousePressed(goLeft),slide(),push(),translate(camLoc.x,camLoc.y);for(let t=0;t<numOfPages;t++)pages[t].run();pop()}function goRight(){movingLeft||isPaused||(movingRight=!0)}function goLeft(){movingRight||isPaused||(movingLeft=!0)}function slide(){movingRight&&!movingLeft&&timer>=0&&(camLoc.x-=20,timer-=20),movingLeft&&!movingRight&&timer>=0&&(camLoc.x+=20,timer-=20),0==timer&&(movingRight=!1,movingLeft=!1,timer=canvas.width/2),-camLoc.x<0&&(camLoc.x=0),-camLoc.x>pages[pages.length-1].loc.x&&(timer=canvas.width/2,movingRight=!1,movingLeft=!1,camLoc.x=-pages[pages.length-1].loc.x)}function keyPressed(){87===keyCode?camLoc.y+=20:83===keyCode?camLoc.y-=20:65===keyCode?camLoc.x+=20:68===keyCode&&(camLoc.x-=20)}class Page{constructor(t,e,i,o,a,s){this.loc=createVector(t,e),this.w=canvas.width/2,this.h=canvas.height/2,this.pageNum=i+1,this.img=o}run(){image(this.img,this.loc.x,this.loc.y,400,400),textSize(20),textAlign(LEFT),textFont(myFont);2==this.pageNum&&(drawtext(this.loc.x+112,this.loc.y+30,txt1),drawtext(this.loc.x+112,this.loc.y+70,txt2),drawtext(this.loc.x+112,this.loc.y+110,txt3),drawtext(this.loc.x+112,this.loc.y+150,txt4),drawtext(this.loc.x+112,this.loc.y+190,txt5)),line(this.loc.x,this.loc.y,this.loc.x+this.w,this.loc.y),line(this.loc.x,this.loc.y,this.loc.x,this.loc.y+this.h),line(this.loc.x,this.loc.y+this.h,this.loc.x+this.w,this.loc.y+this.h),line(this.loc.x+this.w,this.loc.y,this.loc.x+this.w,this.h)}}'
           'let page,camLoc,buttLeft,buttRight,timer,btn,pages=[],numOfPages=3,movingRight=!1,movingLeft=!1,isPaused=!1,defifaBlue=[19,228,240],txt1=[["Prize Pool: ",defifaBlue],[prizePool,defifaBlue],["",defifaBlue]],txt2=[["Phase: ",defifaBlue],[phase,defifaBlue],["",defifaBlue]],txt3=[["Time Remaining: ",defifaBlue],[timeRemaining,defifaBlue],["",defifaBlue]],txt4=[["Total Minted: ",defifaBlue],[totalMinted,defifaBlue],["",defifaBlue]],txt5=[["Burn to Claim: ",defifaBlue],[burnToClaim,defifaBlue],["",defifaBlue]],txt6=[["Team: ",defifaBlue],[tierName,defifaBlue],["",defifaBlue]],pageImg=[];function preload(){pageImg[0]=loadImage("https://gateway.pinata.cloud/ipfs/Qmb4obBzUofeZtcUxhEWUYCmhneZMzCrBQrNGnJnqKNyDq"),pageImg[1]=loadImage("https://ipfs.io/ipfs/QmTSBSHXJgnVg16pjxnH3CAqkL4QDtBwr6aSHkbvhZFmR3"),pageImg[2]=loadImage("https://ipfs.io/ipfs/QmTSBSHXJgnVg16pjxnH3CAqkL4QDtBwr6aSHkbvhZFmR3")}function setup(){myFont=loadFont(font),createCanvas(400,400),camLoc=createVector(0,0);for(let t=0;t<numOfPages;t++)buttLeft=createButton("Artwork"),buttLeft.position(10,canvas.height/2-30),buttRight=createButton("Score Card"),buttRight.style("background-color",color(defifaBlue)),buttRight.position(canvas.width/2-90,canvas.height/2-30),pages[t]=new Page(canvas.width/2*t,0,t,pageImg[t],txt1,0==t?buttLeft:buttRight);timer=canvas.width/2}function drawtext(t,e,i){for(var a=t,o=0;o<i.length;++o){var s=i[o],c=s[0],h=s[1],l=textWidth(c);fill(h),text(c,a,e),a+=l}}function draw(){background(220),buttRight.mousePressed(goRight),buttLeft.mousePressed(goLeft),slide(),push(),translate(camLoc.x,camLoc.y);for(let t=0;t<numOfPages;t++)pages[t].run();pop()}function goRight(){movingLeft||isPaused||(movingRight=!0)}function goLeft(){movingRight||isPaused||(movingLeft=!0)}function slide(){movingRight&&!movingLeft&&timer>=0&&(camLoc.x-=20,timer-=20),movingLeft&&!movingRight&&timer>=0&&(camLoc.x+=20,timer-=20),0==timer&&(movingRight=!1,movingLeft=!1,timer=canvas.width/2),-camLoc.x<0&&(camLoc.x=0),-camLoc.x>pages[pages.length-1].loc.x&&(timer=canvas.width/2,movingRight=!1,movingLeft=!1,camLoc.x=-pages[pages.length-1].loc.x)}function keyPressed(){87===keyCode?camLoc.y+=20:83===keyCode?camLoc.y-=20:65===keyCode?camLoc.x+=20:68===keyCode&&(camLoc.x-=20)}class Page{constructor(t,e,i,a,o,s){this.loc=createVector(t,e),this.w=canvas.width/2,this.h=canvas.height/2,this.pageNum=i+1,this.img=a}run(){image(this.img,this.loc.x,this.loc.y,400,400),textSize(20),textAlign(LEFT),textFont(myFont),2==this.pageNum&&(drawtext(this.loc.x+112,this.loc.y+30,txt6),drawtext(this.loc.x+112,this.loc.y+70,txt1),drawtext(this.loc.x+112,this.loc.y+110,txt2),drawtext(this.loc.x+112,this.loc.y+150,txt3),drawtext(this.loc.x+112,this.loc.y+190,txt4),drawtext(this.loc.x+112,this.loc.y+230,txt6)),this.pageNum,line(this.loc.x,this.loc.y,this.loc.x+this.w,this.loc.y),line(this.loc.x,this.loc.y,this.loc.x,this.loc.y+this.h),line(this.loc.x,this.loc.y+this.h,this.loc.x+this.w,this.loc.y+this.h),line(this.loc.x+this.w,this.loc.y,this.loc.x+this.w,this.h)}}'
        );
 
        requests[2].scriptContent = controllerScript;
        
        // For easier testing, bufferSize for statically stored scripts 
        // is injected in the constructor. Then controller script's length
        // is added to that to find the final buffer size.
        
        uint256 finalBufferSize = BUFFER_SIZE + controllerScript.length;

      // For easier testing, bufferSize is injected in the constructor
      // of this contract.

      bytes memory base64EncodedHTMLDataURI = IScriptyBuilder(_SCRIPTY_BUILDER_ADDRESS)
          .getEncodedHTMLWrapped(requests, finalBufferSize);

      bytes memory metadata = abi.encodePacked(
          '{"name":"p5.js Example - GZIP - Base64", "description":"Assembles GZIP compressed base64 encoded p5.js stored in ethfs FileStore contract with a demo scene. Metadata and animation URL are both base64 encoded.","animation_url":"',
          base64EncodedHTMLDataURI,
          '"}'
      );

      return
          string(
              abi.encodePacked(
                  "data:application/json;base64,",
                  Base64.encode(metadata)
              )
          );
   
    //KMac end
    
    // Get a reference to the tier.
    /* JB721Tier memory _tier = store.tierOfTokenId(address(this), _tokenId);

    _tokenId; // do something with me
    string[] memory parts = new string[](4);
    parts[0] = string('data:application/json;base64,');
    string memory _title = name();
    parts[1] = string(
      abi.encodePacked(
        '{"name":"',
        _title,
        '","description":"Team with ID",',
        '"image":"data:image/svg+xml;base64,'
      )
    );
    string memory _titleFontSize;
    if (bytes(_title).length < 35) _titleFontSize = '24';
    else _titleFontSize = '20';

    string memory _word = _tierNameOf[_tier.id];
    string memory _fontSize;
    if (bytes(_word).length < 3) _fontSize = '240';
    else if (bytes(_word).length < 5) _fontSize = '200';
    else if (bytes(_word).length < 8) _fontSize = '140';
    else if (bytes(_word).length < 10) _fontSize = '90';
    else if (bytes(_word).length < 12) _fontSize = '80';
    else if (bytes(_word).length < 16) _fontSize = '60';
    else if (bytes(_word).length < 23) _fontSize = '40';
    else if (bytes(_word).length < 30) _fontSize = '30';
    else if (bytes(_word).length < 35) _fontSize = '20';
    else _fontSize = '16';

    parts[2] = Base64.encode(
      abi.encodePacked(
        '<svg width="500" height="500" viewBox="0 0 100% 100%" xmlns="http://www.w3.org/2000/svg">',
        '<style>@font-face{font-family:"Capsules-300";src:url(data:font/truetype;charset=utf-8;base64,',
        DefifaFontImporter.getSkinnyFontSource(),
        ');format("opentype");}',
        '@font-face{font-family:"Capsules-700";src:url(data:font/truetype;charset=utf-8;base64,',
        DefifaFontImporter.getBeefyFontSource(),
        ');format("opentype");}',
        'text{fill:#c0b3f1;white-space:pre-wrap; width:100%; }</style>',
        '<rect width="100vw" height="100vh" fill="#181424"/>',
        '<text x="10" y="20" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #be69a7;">DEFIFA</text>',
        '<text x="10" y="40" style="font-size:',
        _titleFontSize,
        'px; font-family: Capsules-300; font-weight:300;">',
        _title,
        '</text>',
        '<text x="10" y="60" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #393059;">GAME ID: 123</text>',
        '<text x="10" y="440" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #393059;">TOKEN ID: 1000003</text>',
        '<text x="10" y="460" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #393059;">VALUE: 3 ETH</text>',
        '<text x="10" y="480" style="font-size:16px; font-family: Capsules-300; font-weight:300; fill: #393059;">RARITY: 1/10</text>',
        '<text textLength="500" lengthAdjust="spacing" x="50%" y="50%" style="font-size:',
        _fontSize,
        'px; font-family: Capsules-700; font-weight:700; text-anchor:middle; dominant-baseline:middle; ">',
        _word,
        '</text>',
        '</svg>'
      )
    );
    parts[3] = string('"}');
    
    string memory uri = string.concat(
      parts[0],
      Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3]))
    ); 
    
    return uri;
    */
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /**
    @param _projectId The ID of the project this contract's functionality applies to.
    @param _directory The directory of terminals and controllers for projects.
    @param _name The name of the token.
    @param _symbol The symbol that the token should be represented by.
    @param _fundingCycleStore A contract storing all funding cycle configurations.
    @param _baseUri A URI to use as a base for full token URIs.
    @param _tokenUriResolver A contract responsible for resolving the token URI for each token ID.
    @param _contractUri A URI where contract metadata can be found. 
    @param _pricing The tier pricing according to which token distribution will be made. Must be passed in order of contribution floor, with implied increasing value.
    @param _store A contract that stores the NFT's data.
    @param _flags A set of flags that help define how this contract works.
  */
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
    string[] memory _tierNames
  ) public override {
    super.initialize(
      _projectId,
      _directory,
      _name,
      _symbol,
      _fundingCycleStore,
      _baseUri,
      _tokenUriResolver,
      _contractUri,
      _pricing,
      _store,
      _flags
    );

    // Keep a reference to the number of tier names.
    uint256 _numberOfTierNames = _tierNames.length;
    
    //_fundingCycleStore = directory.fundingCycleStore();
    JBFundingCycle memory _phase = _fundingCycleStore.currentOf(
            _projectId
        ); 
   
    // Set the name for each tier.
    for (uint256 _i; _i < _numberOfTierNames; ) {
      // Set the tier name.
      _tierNameOf[_i + 1] = _tierNames[_i];
      _tierMintsOf[_i + 1] = store.totalSupply(address(this)); // is thi by tier? or for all tiers?

      unchecked {
        ++_i;
      }
    }
  }

  /** 
    @notice
    Stores the redemption weights that should be used in the end game phase.

    @dev
    Only the contract's owner can set tier redemption weights.

    @param _tierWeights The tier weights to set.
  */
  function setTierRedemptionWeights(DefifaTierRedemptionWeight[] memory _tierWeights)
    external
    override
    onlyOwner
  {
    // Make sure the game has ended.
    if (fundingCycleStore.currentOf(projectId).number < _END_GAME_PHASE)
      revert GAME_ISNT_OVER_YET();

    // Delete the currently set redemption weights.
    delete _tierRedemptionWeights;

    // Keep a reference to the max tier ID.
    uint256 _maxTierId = store.maxTierIdOf(address(this));

    // Keep a reference to the cumulative amounts.
    uint256 _cumulativeRedemptionWeight;

    // Keep a reference to the number of tier weights.
    uint256 _numberOfTierWeights = _tierWeights.length;

    for (uint256 _i; _i < _numberOfTierWeights; ) {
      // Attempting to set the redemption weight for a tier that does not exist (yet) reverts.
      if (_tierWeights[_i].id > _maxTierId) revert INVALID_TIER_ID();

      // Save the tier weight. Tier's are 1 indexed and should be stored 0 indexed.
      _tierRedemptionWeights[_tierWeights[_i].id - 1] = _tierWeights[_i].redemptionWeight;

      // Increment the cumulative amount.
      _cumulativeRedemptionWeight += _tierWeights[_i].redemptionWeight;

      unchecked {
        ++_i;
      }
    }

    // Make sure the cumulative amount is contained within the total redemption weight.
    if (_cumulativeRedemptionWeight > TOTAL_REDEMPTION_WEIGHT) revert INVALID_REDEMPTION_WEIGHTS();
  }

  /**
    @notice
    Part of IJBRedeemDelegate, this function gets called when the token holder redeems. It will burn the specified NFTs to reclaim from the treasury to the _data.beneficiary.

    @dev
    This function will revert if the contract calling is not one of the project's terminals.

    @param _data The Juicebox standard project redemption data.
  */
  function didRedeem(JBDidRedeemData calldata _data) external payable virtual override {
    // Make sure the caller is a terminal of the project, and the call is being made on behalf of an interaction with the correct project.
    if (
      msg.value != 0 ||
      !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender)) ||
      _data.projectId != projectId
    ) revert INVALID_REDEMPTION_EVENT();

    // Check the 4 bytes interfaceId and handle the case where the metadata was not intended for this contract
    // Skip 32 bytes reserved for generic extension parameters.
    if (
      _data.metadata.length < 36 ||
      bytes4(_data.metadata[32:36]) != type(IJB721Delegate).interfaceId
    ) revert INVALID_REDEMPTION_METADATA();

    // Decode the metadata.
    (, , uint256[] memory _decodedTokenIds) = abi.decode(
      _data.metadata,
      (bytes32, bytes4, uint256[])
    );

    // Get a reference to the number of token IDs being checked.
    uint256 _numberOfTokenIds = _decodedTokenIds.length;

    // Keep a reference to the token ID being iterated on.
    uint256 _tokenId;

    // Get a reference to the current funding cycle.
    JBFundingCycle memory _currentFundingCycle = fundingCycleStore.currentOf(projectId);

    // Keep track of whether the redemption is happening during the end phase.
    bool _isEndPhase = _currentFundingCycle.number == _END_GAME_PHASE;

    // Iterate through all tokens, burning them if the owner is correct.
    for (uint256 _i; _i < _numberOfTokenIds; ) {
      // Set the token's ID.
      _tokenId = _decodedTokenIds[_i];

      // Make sure the token's owner is correct.
      if (_owners[_tokenId] != _data.holder) revert UNAUTHORIZED();

      // Burn the token.
      _burn(_tokenId);

      unchecked {
        if (_isEndPhase) ++_redeemedFromTier[store.tierIdOfToken(_tokenId)];
        ++_i;
      }
    }

    // Call the hook.
    _didBurn(_decodedTokenIds);

    // Increment the amount redeemed if this is the end phase.
    if (_isEndPhase) _amountRedeemed += _data.reclaimedAmount.value;
  }

  //*********************************************************************//
  // ------------------------ internal functions ----------------------- //
  //*********************************************************************//

  /**
   @notice
   handles the tier voting accounting

    @param _from The account to transfer voting units from.
    @param _to The account to transfer voting units to.
    @param _tokenId The ID of the token for which voting units are being transferred.
    @param _tier The tier the token ID is part of.
   */
  function _afterTokenTransferAccounting(
    address _from,
    address _to,
    uint256 _tokenId,
    JB721Tier memory _tier
  ) internal virtual override {
    _tokenId; // Prevents unused var compiler and natspec complaints.
    if (_tier.votingUnits != 0) {
      // Delegate the tier to the recipient user themselves if they are not delegating yet
      if (_tierDelegation[_to][_tier.id] == address(0)) {
        _tierDelegation[_to][_tier.id] = _to;
        emit DelegateChanged(_to, address(0), _to);
      }

      // Transfer the voting units.
      _transferTierVotingUnits(_from, _to, _tier.id, _tier.votingUnits);
    }
  }
}
