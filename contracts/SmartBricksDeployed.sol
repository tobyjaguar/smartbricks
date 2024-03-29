// Implemented from the SmartPiggies contract

/**
SmartPiggies is an open source standard for
a free peer to peer global derivatives market

Copyright (C) 2019, Arief, Algya, Lee

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
**/
pragma solidity >=0.4.24 <0.6.0;
pragma experimental ABIEncoderV2;

interface PaymentToken {
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function transfer(address to, uint256 value) external returns (bool);
  function decimals() external returns (uint8);
}

import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/introspection/ERC165.sol";
import "https://github.com/OpenZeppelin/openzeppelin-solidity/contracts/math/SafeMath.sol";

/** @title SmartBricks: A Smart Piggies Implementation
*/
contract SmartBricks is ERC165 {
  using SafeMath for uint256;

  address payable owner;
  uint256 public tokenId;

  struct DetailAddresses {
    address writer;
    address holder;
    address collateralERC;
    address dataResolver;
  }

  struct DetailUints {
    uint256 collateral;
    uint256 lotSize;
    uint256 strikePrice;
    uint256 expiry;
    uint256 settlementPrice;
    uint256 reqCollateral;
    uint8 collateralDecimals;  // to store decimals from ERC-20 contract
  }

  struct BoolFlags {
    bool isRequest;
    bool isEuro;
    bool isPut;
    bool hasBeenCleared;  // to flag whether the oracle returned a callback w/ price
  }

  struct DetailAuction {
    uint256 startBlock;
    uint256 expiryBlock;
    uint256 startPrice;
    uint256 reservePrice;
    uint256 timeStep;
    uint256 priceStep;
    bool auctionActive;
    bool satisfyInProgress;  // mutex guard to disallow ending an auction if a transaction to satisfy is in progress
  }

  struct Piggy {
    DetailAddresses addresses; //address details
    DetailUints uintDetails; //number details
    BoolFlags flags; //parameter switches
  }

  mapping (address => mapping(address => uint256)) private ERC20balances;
  mapping (address => uint256[]) private ownedPiggies; //again, public?
  mapping (uint256 => uint256) private ownedPiggiesIndex;
  mapping (uint256 => Piggy) private piggies;
  mapping (uint256 => DetailAuction) private auctions;

  /*
  add events
  */

  event CreatePiggy(
    address[] indexed addresses,
    uint256[] indexed ints,
    bool[] indexed bools
  );

  event TransferPiggy(
    address indexed from,
    address indexed to,
    uint256 indexed tokenId
  );

  event UpdateRFP(
    address indexed from,
    uint256 indexed tokenId,
    address collateralERC,
    address dataResolver,
    uint256 reqCollateral,
    uint256 lotSize,
    uint256 strikePrice,
    uint256 expiry,
    bool isEuro,
    bool isPut
  );

  event ReclaimAndBurn(
    address indexed from,
    uint256 indexed tokenId,
    bool indexed RFP
  );

  event StartAuction(
    address indexed from,
    uint256 indexed tokenId,
    uint256 startPrice,
    uint256 reservePrice,
    uint256 auctionLength,
    uint256 timeStep,
    uint256 priceStep
  );

  event EndAuction(
    address indexed from,
    uint256 indexed tokenId,
    bool indexed RFP
  );

  event SatisfyAuction(
    address indexed from,
    uint256 indexed tokenId,
    uint256 paidPremium,
    uint256 change,
    uint256 auctionPremium
  );

  event RequestSettlementPrice(
    address indexed feePayer,
    uint256 indexed tokenId,
    uint256 oracleFee,
    address dataResolver
  );

  event OracleReturned(
    address indexed resolver,
    uint256 indexed tokenId,
    uint256 indexed price
  );

  event SettlePiggy(
   address indexed from,
   uint256 indexed tokenId,
   uint256 indexed holderPayout,
   uint256 writerPayout
  );

  event ClaimPayout(
    address indexed from,
    uint256 indexed amount,
    address indexed paymentToken
  );

  /**
    constructor should throw if various things aren't properly set
    also should throw if the contract is not delegated an amount of collateral designated
    in the reference ERC-20 which is >= the collateral value of the piggy
  */
  constructor()
    public
  {
    //declarations here
    owner = msg.sender;
  }

  /** @notice Create a new token
      @param _collateralERC The address of the reference ERC-20 token to be used as collateral
      param _dataResolver The address of a service contract which will return the settlement price
      @param _collateral The amount of collateral for the option, denominated in units of the token
       at the `_collateralERC` address
      @param _lotSize A multiplier on the settlement price used to determine settlement claims
      @param _strikePrice The strike value of the option, in the same units as the settlement price
      @param _expiry The block height at which the option will expire
      @param _isEuro If true, the option can only be settled at or after `_expiry` is reached, else
       it can be settled at any time
      @param _isPut If true, the settlement claims will be calculated for a put option; else they
       will be calculated for a call option
      @param _isRequest If true, will create the token as an "RFP" / request for a particular option
  */
  function createPiggy(
    address _collateralERC,
    address _dataResolver,
    uint256 _collateral,
    uint256 _lotSize,
    uint256 _strikePrice,
    uint256 _expiry,
    bool _isEuro,
    bool _isPut,
    bool _isRequest
  )
    public
    returns (bool)
  {
    require(
      _collateralERC != address(0) &&
      _dataResolver != address(0),
      "addresses cannot be zero"
    );
    require(
      _collateral != 0 &&
      _lotSize != 0 &&
      _strikePrice != 0 &&
      _expiry != 0,
      "option parameters cannot be zero"
    );
    // if not an RFP, make sure the collateral can be transferred
    if (!_isRequest) {
      bool success = attemptPaymentTransfer(
        _collateralERC, //_collateralERC
        msg.sender,
        address(this),
        _collateral
      );
      require(success, "Token transfer did not complete");
    }
    // any other checks that need to be performed specifically for RFPs ?

    require(
      _constructPiggy(
        _collateralERC,
        _dataResolver,
        _collateral,
        _lotSize,
        _strikePrice,
        _expiry,
        0,
        _isEuro,
        _isPut,
        _isRequest,
        false
      ),
      "failed to create piggy"
    );


    return true;
  }

  function splitPiggy(
    uint256 _tokenId
  )
    public
    returns (bool)
  {
    require(_tokenId != 0, "token ID cannot be zero");
    require(piggies[_tokenId].addresses.writer != address(0), "token writer cannot be a zero address");
    require(!piggies[_tokenId].flags.isRequest, "token cannot be an RFP");
    require(piggies[_tokenId].uintDetails.collateral > 0, "token collateral must be greater than zero");
    require(piggies[_tokenId].addresses.holder == msg.sender, "only the holder can split");
    require(block.number < piggies[_tokenId].uintDetails.expiry, "cannot split expired token");
    require(!auctions[_tokenId].auctionActive, "cannot split token on auction");
    require(!piggies[_tokenId].flags.hasBeenCleared, "cannot split token that has been cleared");

    // assuming all checks have passed:

    //calculate collateral split
    uint256 splitCollateral = piggies[tokenId].uintDetails.collateral.div(2);

    //remove current token ID
    _removeTokenFromOwnedPiggies(msg.sender, _tokenId); //should this be piggies[_tokenId].holder

    require(
      _constructPiggy(
        piggies[_tokenId].addresses.collateralERC,
        piggies[_tokenId].addresses.dataResolver,
        piggies[tokenId].uintDetails.collateral.sub(splitCollateral), //accounting for interger division
        piggies[_tokenId].uintDetails.lotSize,
        piggies[_tokenId].uintDetails.strikePrice,
        piggies[_tokenId].uintDetails.expiry,
        _tokenId,
        piggies[_tokenId].flags.isEuro,
        piggies[_tokenId].flags.isPut,
        false, //piggies[tokenId].isRequest
        true //split piggy
      ),
      "failed to create a new piggy"
    ); //check to make sure this rolls back the reset if it fails

    require(
      _constructPiggy(
        piggies[_tokenId].addresses.collateralERC,
        piggies[_tokenId].addresses.dataResolver,
        splitCollateral,
        piggies[_tokenId].uintDetails.lotSize,
        piggies[_tokenId].uintDetails.strikePrice,
        piggies[_tokenId].uintDetails.expiry,
        _tokenId,
        piggies[_tokenId].flags.isEuro,
        piggies[_tokenId].flags.isPut,
        false, //piggies[tokenId].isRequest
        true //split piggy
      ),
      "failed to make a new piggy"
    ); //check to make sure this rolls back the reset if it fails

    //clean up piggyId
    _resetPiggy(_tokenId);

    return true;
  }

  function transferFrom(address _from, address _to, uint256 _tokenId)
    public
  {
    require(msg.sender == piggies[_tokenId].addresses.holder, "msg.sender is not the owner"); //openzep doesn't do this
    _internalTransfer(_from, _to, _tokenId);
  }

  // possibly add function to update reqCollateral if token is an RFP and hasn't been successfully fulfilled
  // maybe allow all fields of an RFP to be updated ?
  // this may be more trouble than it is worth. could allow this function to accept a struct, and check if any keys matching fields of Piggy are nonzero, if so, update those ones
  function updateRFP(
    uint256 _tokenId,
    address _collateralERC,
    address _dataResolver,
    uint256 _reqCollateral,
    uint256 _lotSize,
    uint256 _strikePrice,
    uint256 _expiry,
    bool _isEuro,  // MUST be specified
    bool _isPut    // MUST be specified
  )
    public
    returns (bool)
  {
    require(piggies[_tokenId].addresses.holder == msg.sender, "you must own the RFP to update it");
    require(piggies[_tokenId].flags.isRequest, "you can only update an RFP");
    uint256 expiryBlock;
    if (_collateralERC != address(0)) {
      piggies[_tokenId].addresses.collateralERC = _collateralERC;
    }
    if (_dataResolver != address(0)) {
      piggies[_tokenId].addresses.dataResolver = _dataResolver;
    }
    if (_reqCollateral != 0) {
      piggies[_tokenId].uintDetails.reqCollateral = _reqCollateral;
    }
    if (_lotSize != 0) {
      piggies[_tokenId].uintDetails.lotSize = _lotSize;
    }
    if (_strikePrice != 0 ) {
      piggies[_tokenId].uintDetails.strikePrice = _strikePrice;
    }
    if (_expiry != 0) {
      // should this redo the expiry calculation? to be consistent w/ how the creation function works ?
      expiryBlock = _expiry.add(block.number);
      piggies[_tokenId].uintDetails.expiry = expiryBlock;
    }
    piggies[_tokenId].flags.isEuro = _isEuro;
    piggies[_tokenId].flags.isPut = _isPut;

    emit UpdateRFP(
      msg.sender,
      _tokenId,
      _collateralERC,
      _dataResolver,
      _reqCollateral,
      _lotSize,
      _strikePrice,
      expiryBlock,
      _isEuro,
      _isPut
    );

    return true;
  }

  // this function can be used to burn any token; if it is an option, will return collateral before burning
  function reclaimAndBurn(uint256 _tokenId)
    public
    returns (bool)
  {
    require(msg.sender == piggies[_tokenId].addresses.holder, "you must own the token to burn it");
    require(!auctions[_tokenId].auctionActive, "you cannot burn a token which is on auction");
    if (!piggies[_tokenId].flags.isRequest) {
      require(msg.sender == piggies[_tokenId].addresses.writer, "you must own the collateral to reclaim it");
      // return the collateral to sender
      PaymentToken(piggies[_tokenId].addresses.collateralERC).transfer(msg.sender, piggies[_tokenId].uintDetails.collateral);
    }
    emit ReclaimAndBurn(msg.sender, _tokenId, piggies[_tokenId].flags.isRequest);
    //remove id from index mapping
    _removeTokenFromOwnedPiggies(piggies[_tokenId].addresses.holder, _tokenId);
    // burn the token (zero out storage fields)
    _resetPiggy(_tokenId);
    return true;
  }

  function startAuction(
    uint256 _tokenId,
    uint256 _startPrice,
    uint256 _reservePrice,
    uint256 _auctionLength,
    uint256 _timeStep,
    uint256 _priceStep
  )
    external
    returns (bool)
  {
    uint256 _auctionExpiry = block.number.add(_auctionLength);
    require(piggies[_tokenId].addresses.holder == msg.sender, "you must own a token to auction it");
    require(piggies[_tokenId].uintDetails.expiry > block.number, "option must not be expired");
    require(piggies[_tokenId].uintDetails.expiry > _auctionExpiry, "auction cannot expire after the option");
    require(!piggies[_tokenId].flags.hasBeenCleared, "option cannot have been cleared");
    require(!auctions[_tokenId].auctionActive, "auction cannot already be running");
    // as specified below, this is not needed if we change the function (as I have done) to accept an _auctionLength rather than a direct _auctionExpiry value
    //require(_auctionExpiry > block.number, "auction must expire in the future");  // DO WE WANT TO ALSO ADD A BUFFER HERE? LIKE IT MUST EXPIRE AT LEAST XX BLOCKS IN THE FUTURE?
    if (piggies[_tokenId].flags.isRequest) {
      bool success = attemptPaymentTransfer(
        piggies[_tokenId].addresses.collateralERC,
        msg.sender,
        address(this),
        _reservePrice  // this should be the max the requestor is willing to pay in a reverse dutch auction
      );
      require(success, "transferFrom did not return true");
    }
    // if we made it past the various checks, set the auction metadata up in auctions mapping
    auctions[_tokenId].startBlock = block.number;
    auctions[_tokenId].expiryBlock = _auctionExpiry;
    auctions[_tokenId].startPrice = _startPrice;
    auctions[_tokenId].reservePrice = _reservePrice;
    auctions[_tokenId].timeStep = _timeStep;
    auctions[_tokenId].priceStep = _priceStep;
    auctions[_tokenId].auctionActive = true;

    emit StartAuction(
      msg.sender,
      _tokenId,
      _startPrice,
      _reservePrice,
      _auctionLength,
      _timeStep,
      _priceStep
    );

    return true;
  }

  function endAuction(uint256 _tokenId)
    public
    returns (bool)
  {
    require(piggies[_tokenId].addresses.holder == msg.sender, "you must own a token to auction it");
    require(auctions[_tokenId].auctionActive, "auction must be active to cancel it");
    require(!auctions[_tokenId].satisfyInProgress, "auction cannot be in the process of being satisfied");  // this should be added to other functions as well
    if (piggies[_tokenId].flags.isRequest) {
      // refund the _reservePrice premium
      uint256 _premiumToReturn = auctions[_tokenId].reservePrice;
      //auctions[_tokenId].reservePrice = 0;  // this sort of offends my sensibilities because we only zero out one auction param, but it is the only one required to change for this logic to work
      PaymentToken(piggies[_tokenId].addresses.collateralERC).transfer(msg.sender, _premiumToReturn);
    }
    _clearAuctionDetails(_tokenId);
    emit EndAuction(msg.sender, _tokenId, piggies[_tokenId].flags.isRequest);
    return true;
  }

  // consider possible attacks and refactor if needed
  function satisfyAuction(uint256 _tokenId)
    public
    returns (bool)
  {
    require(!auctions[_tokenId].satisfyInProgress, "cannot reenter this function while it is in progress");
    require(piggies[_tokenId].addresses.holder != msg.sender, "cannot satisfy your own auction; use endAuction instead");
    require(auctions[_tokenId].auctionActive, "auction must be active to satisfy it");
    // if auction is "active" according to state but has expired, change state
    if (auctions[_tokenId].expiryBlock < block.number) {
      //auctions[_tokenId].auctionActive = false;  // handled by _clearAuctionDetails now
      _clearAuctionDetails(_tokenId);
      return false;
    }
    // get linear auction premium; reserve price should be a ceiling or floor depending on whether this is an RFP or an option, respectively
    uint256 _auctionPremium = getAuctionPrice(_tokenId);
    // lock mutex
    auctions[_tokenId].satisfyInProgress = true;
    if (piggies[_tokenId].flags.isRequest) {
      // msg.sender needs to delegate reqCollateral
      bool success = attemptPaymentTransfer(
        piggies[_tokenId].addresses.collateralERC,
        msg.sender,
        address(this),
        piggies[_tokenId].uintDetails.reqCollateral
      );
      if (!success) {
        auctions[_tokenId].satisfyInProgress = false;
        return false;
      }
      // if the collateral transfer succeeded, collateral gets set to reqCollateral
      piggies[_tokenId].uintDetails.collateral = piggies[_tokenId].uintDetails.reqCollateral;
      // calculate adjusted premium (based on reservePrice) + possible change due back to current holder
      uint256 _change = 0;
      uint256 _adjPremium = _auctionPremium;
      if (_adjPremium > auctions[_tokenId].reservePrice) {
        _adjPremium = auctions[_tokenId].reservePrice;
      } else {
        _change = auctions[_tokenId].reservePrice.sub(_adjPremium);
      }
      // current holder pays premium (via amount already delegated to this contract in startAuction)
      PaymentToken(piggies[_tokenId].addresses.collateralERC).transfer(msg.sender, _adjPremium);
      // current holder receives any change due
      if (_change > 0) {
        PaymentToken(piggies[_tokenId].addresses.collateralERC).transfer(piggies[_tokenId].addresses.holder, _change);
      }
      // isRequest becomes false
      piggies[_tokenId].flags.isRequest = false;
      // msg.sender becomes writer
      piggies[_tokenId].addresses.writer = msg.sender;

      emit SatisfyAuction(
        msg.sender,
        _tokenId,
        _adjPremium,
        _change,
        _auctionPremium
      );

    } else {
      // calculate the adjusted premium based on reservePrice
      uint256 _adjPremium = _auctionPremium;
      if (_adjPremium < auctions[_tokenId].reservePrice) {
        _adjPremium = auctions[_tokenId].reservePrice;
      }
      // msg.sender pays (adjusted) premium
      bool success = attemptPaymentTransfer(
        piggies[_tokenId].addresses.collateralERC,
        msg.sender,
        piggies[_tokenId].addresses.holder,  // should the SP contract escrow it first?
        _adjPremium
      );
      if (!success) {
        auctions[_tokenId].satisfyInProgress = false;
        return false;
      }
      // msg.sender becomes holder
      _internalTransfer(piggies[_tokenId].addresses.holder, msg.sender, _tokenId);

      emit SatisfyAuction(
        msg.sender,
        _tokenId,
        _adjPremium,
        0,
        _auctionPremium
      );

    }
    // auction is ended
    _clearAuctionDetails(_tokenId);
    // mutex released
    auctions[_tokenId].satisfyInProgress = false;
    return true;
  }

  /** @notice Call the oracle to fetch the settlement price
      @dev Throws if `_tokenId` is not a valid token.
       Throws if `_oracle` is not a valid contract address.
       Throws if `onMarket(_tokenId)` is true.
       If `isEuro` is true for the specified token, throws if `_expiry` > block.number.
       If `isEuro` is true for the specified token, throws if `_priceNow` is true. [OR specify that it flips that to false always (?)]
       If `priceNow` is true, throws if block.number > `_expiry` for the specified token.
       If `priceNow` is false, throws if block.number < `_expiry` for the specified token.
       If `priceNow` is true, calls the oracle to request the `_underlyingNow` value for the token.
       If `priceNow` is false, calls the oracle to request the `_underlyingExpiry` value for the token.
       Depending on the oracle service implemented, additional state will need to be referenced in
       order to call the oracle, e.g. an endpoint to fetch. This state handling will need to be
       managed on an implementation basis for specific oracle services.
      @param _tokenId The identifier of the token
      @param _oracleFee Fee paid to oracle service
        A value needs to be provided for this function to succeed
        If the oracle doesn't need payment, include a positive garbage value
      @return The settlement price from the oracle to be used in `settleOption()`
   */
  function requestSettlementPrice(uint256 _tokenId, uint256 _oracleFee) // this should be renamed perhaps, s.t. it is obvious that this is the "clearing phase"
    public
    returns (bool)
  {
    require(msg.sender != address(0), "sender cannot be the zero address");
    //what check should be done to check that piggy is active?
    require(!auctions[_tokenId].auctionActive, "cannot clear a token while auction is active");
    require(!piggies[_tokenId].flags.hasBeenCleared, "token has already been cleared");  // this is potentially problematic in the case of "garbage data"
    require(_tokenId != 0, "_tokenId cannot be zero");
    require(_oracleFee != 0, "oracle fee cannot be zero");
    //if Euro require past expiry
    if (piggies[_tokenId].flags.isEuro) {
      require(piggies[_tokenId].uintDetails.expiry <= block.number);
    }
    //fetch data from dataResolver contract
    address _dataResolver;
    if (piggies[_tokenId].flags.isEuro || (piggies[_tokenId].uintDetails.expiry < block.number))
    {
      _dataResolver = piggies[_tokenId].addresses.dataResolver; //changed from dataResolverAtExpiry
    } else {
      require(msg.sender == piggies[_tokenId].addresses.holder, "only the holder can settle an American style option before expiry");
      _dataResolver = piggies[_tokenId].addresses.dataResolver;
    }
    require(_callResolver(_dataResolver, msg.sender, _oracleFee, _tokenId), "call to resolver did not return true");
    return true;
  }

  function _callback(
    uint256 _tokenId,
    uint256 _price
  )
    public
  {
    address _dataResolver;
    if (piggies[_tokenId].flags.isEuro || (piggies[_tokenId].uintDetails.expiry < block.number))
    {
      _dataResolver = piggies[_tokenId].addresses.dataResolver; // changed from dataResolverAtExpiry
    } else {
      _dataResolver = piggies[_tokenId].addresses.dataResolver;
    }
    require(msg.sender == _dataResolver, "resolve address was not correct"); // MUST restrict a call to only the resolver address
    piggies[_tokenId].uintDetails.settlementPrice = _price;
    piggies[_tokenId].flags.hasBeenCleared = true;

    emit OracleReturned(
      msg.sender,
      _tokenId,
      _price
    );

  }

  /** @notice Calculate the settlement of ownership of option collateral
      @dev Throws if `_tokenId` is not a valid ERC-59 token.
       Throws if msg.sender is not one of: seller, owner of `_tokenId`.
       Throws if `hasSettlementPrice(_tokenId)` is false.
   */
   function settlePiggy(uint256 _tokenId)
     public
     returns (bool)
   {
     require(msg.sender != address(0), "msg.sender cannot be zero");
     require(_tokenId != 0, "tokenId cannot be zero");
     require(piggies[_tokenId].flags.hasBeenCleared, "piggy has not received an oracle price");

     uint256 payout;

     if(piggies[_tokenId].flags.isEuro) {
       require(piggies[_tokenId].uintDetails.expiry <= block.number, "European option needs to be expired");
     }
     payout = _calculateLongPayout(
         piggies[_tokenId].flags.isPut,
         piggies[_tokenId].uintDetails.settlementPrice,
         piggies[_tokenId].uintDetails.strikePrice,
         piggies[_tokenId].uintDetails.lotSize,
         piggies[_tokenId].uintDetails.collateralDecimals
     );

     // set the balances of the two counterparties based on the payout
     address _writer = piggies[_tokenId].addresses.writer;
     address _holder = piggies[_tokenId].addresses.holder;
     address _collateralERC = piggies[_tokenId].addresses.collateralERC;

     if (payout > piggies[_tokenId].uintDetails.collateral) {
       payout = piggies[_tokenId].uintDetails.collateral;
     }
     ERC20balances[_holder][_collateralERC] = ERC20balances[_holder][_collateralERC].add(payout);
     ERC20balances[_writer][_collateralERC] = piggies[_tokenId].uintDetails.collateral.sub(payout);

     emit SettlePiggy(
       msg.sender,
       _tokenId,
       payout,
       piggies[_tokenId].uintDetails.collateral.sub(payout)
     );

     _removeTokenFromOwnedPiggies(_holder, _tokenId);
     //clean up piggyId
     _resetPiggy(_tokenId);
     return true;
   }

  // claim payout - pull payment
  // sends any reference ERC-20 which the _claimant is owed (as a result of an auction or settlement)
  function claimPayout(address _paymentToken, uint256 _amount)
    public
    returns (bool)
  {
    require(_amount <= ERC20balances[msg.sender][_paymentToken], "ERC20 balance is less than requested amount");
    ERC20balances[msg.sender][_paymentToken] = ERC20balances[msg.sender][_paymentToken].sub(_amount);
    //require(token(_stableToken).transfer(msg.sender, balanceOf(msg.sender))), "Unable to transfer");
    (bool success, ) = address(PaymentToken(_paymentToken)).call(
      abi.encodeWithSignature(
        "transfer(address,uint256)",
        msg.sender,
        _amount
      )
    );
    require(success, "ERC20 token transfer failed");

    emit ClaimPayout(
      msg.sender,
      _amount,
      _paymentToken
    );

    return true;
  }

  /** Helper functions
  */
  // helper function to view info from about the piggy outside of the contract
  function getDetails(uint256 _tokenId)
    public
    view
    returns (Piggy memory)
  {
    return piggies[_tokenId];
  }

  // this is a helper function to allow view of auction details
  function getAuctionDetails(uint256 _tokenId)
    public
    view
    returns (DetailAuction memory)
  {
    return auctions[_tokenId];
  }

  /** @notice Count the number of ERC-59 tokens owned by a particular address
      @dev ERC-59 tokens assigned to the zero address are considered invalid, and this
       function throws for queries about the zero address.
      @param _owner An address for which to query the balance of ERC-59 tokens
      @return The number of ERC-59 tokens owned by `_owner`, possibly zero
   */
  function getOwnedPiggies(address _owner)
    public
    view
    returns (uint256[] memory)
  {
    require(_owner != address(0), "address cannot be zero");
    return ownedPiggies[_owner];
  }

  function getERC20balance(address _owner, address _erc20)
    public
    view
    returns (uint256)
  {
    require(_owner != address(0), "address cannot be zero");
    return ERC20balances[_owner][_erc20];
  }

  function _constructPiggy(
    address _collateralERC,
    address _dataResolver,
    uint256 _collateral,
    uint256 _lotSize,
    uint256 _strikePrice,
    uint256 _expiry,
    uint256 _splitTokenId,
    bool _isEuro,
    bool _isPut,
    bool _isRequest,
    bool _isSplit
  )
    internal
    returns (bool)
  {
    // assuming all checks have passed:
    uint256 tokenExpiry;
    tokenId = tokenId.add(1);

    // write the values to storage, including _isRequest flag
    Piggy storage p = piggies[tokenId];
    p.addresses.holder = msg.sender;
    p.addresses.collateralERC = _collateralERC;
    p.addresses.dataResolver = _dataResolver;
    p.uintDetails.lotSize = _lotSize;
    p.uintDetails.strikePrice = _strikePrice;
    p.flags.isEuro = _isEuro;
    p.flags.isPut = _isPut;
    p.flags.isRequest = _isRequest;

    // conditional state variable assignments based on _isRequest:
    if (_isRequest) {
      tokenExpiry = _expiry.add(block.number);
      p.uintDetails.reqCollateral = _collateral;
      p.uintDetails.collateralDecimals = _getERC20Decimals(_collateralERC);
      p.uintDetails.expiry = tokenExpiry;
    } else if (_isSplit) {
      require(_splitTokenId != 0, "token ID cannot be zero");
      require(!piggies[_splitTokenId].flags.isRequest, "token cannot be an RFP");
      require(piggies[_splitTokenId].addresses.holder == msg.sender, "only the holder can split");
      require(block.number < piggies[_splitTokenId].uintDetails.expiry, "cannot split expired token");
      require(!auctions[_splitTokenId].auctionActive, "cannot split token on auction");
      require(!piggies[_splitTokenId].flags.hasBeenCleared, "cannot split token that has been cleared");
      tokenExpiry = piggies[_splitTokenId].uintDetails.expiry;
      p.addresses.writer = piggies[_splitTokenId].addresses.writer;
      p.uintDetails.collateral = _collateral;
      p.uintDetails.collateralDecimals = piggies[_splitTokenId].uintDetails.collateralDecimals;
      p.uintDetails.expiry = tokenExpiry;
    } else {
      require(!_isSplit, "split cannot be true when creating a new piggy");
      tokenExpiry = _expiry.add(block.number);
      p.addresses.writer = msg.sender;
      p.uintDetails.collateral = _collateral;
      p.uintDetails.collateralDecimals = _getERC20Decimals(_collateralERC);
      p.uintDetails.expiry = tokenExpiry;
    }

    _addTokenToOwnedPiggies(msg.sender, tokenId);

    address[] memory a = new address[](2);
    a[0] = msg.sender;
    a[1] = _dataResolver;

    uint256[] memory i = new uint256[](4);
    i[0] = tokenId;
    i[1] = _collateral;
    i[2] = _lotSize;
    i[1] = tokenExpiry;

    bool[] memory b = new bool[](3);
    b[0] = _isEuro;
    b[1] = _isPut;
    b[2] = _isRequest;

    emit CreatePiggy(
      a,
      i,
      b
    );

    return true;
  }

  // make sure the ERC-20 contract for collateral correctly reports decimals
  function _getERC20Decimals(address _ERC20)
    internal
    returns (uint8)
  {
    (bool success, bytes memory _decBytes) = address(PaymentToken(_ERC20)).call(
        abi.encodeWithSignature("decimals()")
      );
     require(success, "collateral ERC-20 contract does not properly specify decimals");
     // convert bytes to uint8:
     uint256 _ERCdecimals;
     for(uint256 i=0; i < _decBytes.length; i++) {
       _ERCdecimals = _ERCdecimals + uint8(_decBytes[i])*(2**(8*(_decBytes.length-(i+1))));
     }
     return uint8(_ERCdecimals);
  }

  // internal transfer for transfers made on behalf of the contract
  function _internalTransfer(address _from, address _to, uint256 _tokenId)
    internal
  {
    require(_from == piggies[_tokenId].addresses.holder, "from address is not the owner");
    require(_to != address(0), "to address is zero");
    _removeTokenFromOwnedPiggies(_from, _tokenId);
    _addTokenToOwnedPiggies(_to, _tokenId);
    piggies[_tokenId].addresses.holder = _to;
    emit TransferPiggy(_from, _to, _tokenId);
  }

  function _clearAuctionDetails(uint256 _tokenId)
    internal
  {
    auctions[_tokenId].startBlock = 0;
    auctions[_tokenId].expiryBlock = 0;
    auctions[_tokenId].startPrice = 0;
    auctions[_tokenId].reservePrice = 0;
    auctions[_tokenId].timeStep = 0;
    auctions[_tokenId].priceStep = 0;
    auctions[_tokenId].auctionActive = false;
  }

  // calculate the price for satisfaction of an auction
  // this is an interpolated linear price based on the supplied auction parameters at a resolution of 1 block
  function getAuctionPrice(uint256 _tokenId)
    internal
    view
    returns (uint256)
  {

    uint256 _pStart = auctions[_tokenId].startPrice;
    uint256 _pDelta = (block.number).sub(auctions[_tokenId].startBlock).mul(auctions[_tokenId].priceStep).div(auctions[_tokenId].timeStep);
    if (piggies[_tokenId].flags.isRequest) {
      return _pStart.add(_pDelta);
    } else {
      return (_pStart.sub(_pDelta));
    }
  }

  function _callResolver(address _dataResolver, address _feePayer, uint256 _oracleFee, uint256 _tokenId)
    internal
    returns (bool)
  {
    (bool success, ) = address(_dataResolver).call(
      abi.encodeWithSignature("fetchData(address,uint256,uint256)", _feePayer, _oracleFee, _tokenId)
    );
    require(success, "fetch success did not return true");

    emit RequestSettlementPrice(
      _feePayer,
      _tokenId,
      _oracleFee,
      _dataResolver
    );

    return true;
  }

  function _calculateLongPayout(
    bool _isPut,
    uint256 _exercisePrice,
    uint256 _strikePrice,
    uint256 _lotSize,
    uint8 _decimals
  )
    internal
    pure
    returns (uint256 _payout)
  {
    if (_isPut && (_strikePrice > _exercisePrice)) {
      _payout = _strikePrice.sub(_exercisePrice);
    }
    if (!_isPut && (_exercisePrice > _strikePrice)) {
      _payout = _exercisePrice.sub(_strikePrice);
    }
    _payout = _payout.mul(10**uint256(_decimals)).mul(_lotSize).div(100);
    return _payout;
  }

  // abstract ERC-20 TransferFrom attepmts
  function attemptPaymentTransfer(address _ERC20, address _from, address _to, uint256 _amount)
    private
    returns (bool)
  {
    (bool success, ) = address(PaymentToken(_ERC20)).call(
      abi.encodeWithSignature(
        "transferFrom(address,address,uint256)",
        _from,
        _to,
        _amount
      )
    );
    return success;
  }

  function _addTokenToOwnedPiggies(address _to, uint256 _tokenId)
    private
  {
    ownedPiggiesIndex[_tokenId] = ownedPiggies[_to].length;
    ownedPiggies[_to].push(_tokenId);
  }

  function _removeTokenFromOwnedPiggies(address _from, uint256 _tokenId)
    private
  {
    uint256 lastTokenIndex = ownedPiggies[_from].length.sub(1);
    uint256 tokenIndex = ownedPiggiesIndex[_tokenId];

    if (tokenIndex != lastTokenIndex) {
      uint256 lastTokenId = ownedPiggies[_from][lastTokenIndex];
      ownedPiggies[_from][tokenIndex] = lastTokenId;
      ownedPiggiesIndex[lastTokenId] = tokenIndex;
    }
    ownedPiggies[_from].length--;
  }

  function _resetPiggy(uint256 _tokenId)
    private
  {
    piggies[_tokenId].addresses.writer = address(0);
    piggies[_tokenId].addresses.holder = address(0);
    piggies[_tokenId].addresses.collateralERC = address(0);
    piggies[_tokenId].addresses.dataResolver = address(0);
    piggies[_tokenId].uintDetails.collateral = 0;
    piggies[_tokenId].uintDetails.lotSize = 0;
    piggies[_tokenId].uintDetails.strikePrice = 0;
    piggies[_tokenId].uintDetails.expiry = 0;
    piggies[_tokenId].uintDetails.settlementPrice = 0;
    piggies[_tokenId].uintDetails.reqCollateral = 0;
    piggies[_tokenId].uintDetails.collateralDecimals = 0;
    piggies[_tokenId].flags.isRequest = false;
    piggies[_tokenId].flags.isEuro = false;
    piggies[_tokenId].flags.isPut = false;
    piggies[_tokenId].flags.hasBeenCleared = false;
  }

  function getOwner()
    public
    view
    returns (address)
  {
    return owner;
  }
  function changeOwner(address payable _newAddress)
    public
    returns (bool)
  {
    require(msg.sender == owner);
    owner = _newAddress;
  }
  function kill()
    public
  {
    require(msg.sender == owner);
    selfdestruct(owner);
  }
}
