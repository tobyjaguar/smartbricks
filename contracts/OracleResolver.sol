// Chainlink mainnet resolver
pragma solidity >=0.4.24 <0.6.0;

import "https://github.com/smartcontractkit/chainlink/blob/develop//evm/contracts/ChainlinkClient.sol";

interface OracleToken {
  function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract OracleResolver is ChainlinkClient {
  address public owner;
  bytes32 public lastId;
  string public dataSource;
  string public underlying;
  string public oracle;
  string public endpoint; // https://api.coincap.io/v2/assets/ethereum
  string public path; // data.priceUsd
  uint256 public tokenId;

  bytes32 public jobId; // 1b8ba62828ea4abbba0912a1bf297d25
  uint256 public price;
  address public oracleAddress; // 0x89f70fA9F439dbd0A1BC22a09BEFc56adA04d9b4
  address public LINKTokenAddress; // 0x514910771af9ca656af840dff83e8264ecf986ca

  mapping(bytes32 => address) public callers;

  struct Request {
    address requester;
    address payee;
    uint256 tokenId;
  }

  mapping(bytes32 => Request) public requests;

  constructor(
    string memory _dataSource,
    string memory _underlying,
    string memory _oracleService,
    bytes32 _jobId,
    string memory _endpoint,
    string memory _path,
    uint256 _price,
    address _oracleAddress,
    address _LinkTokenAddress
  )
    public
  {
    owner = msg.sender;
    dataSource = _dataSource;
    underlying = _underlying;
    oracle = _oracleService;
    jobId = bytes32(_jobId);
    endpoint = _endpoint;
    path = _path;
    price = _price;
    oracleAddress = _oracleAddress;
    LINKTokenAddress = _LinkTokenAddress;
  }

  // this function may now no longer need to exist separately; i'm lazy and don't want to rewrite everything atm though
  function fetchData(address _funder, uint256 _oracleFee, uint256 _tokenId)
    public
    returns (bool)
  {
    require(
      address(LINKTokenAddress).call(
        bytes4(
          keccak256("transferFrom(address,address,uint256)")),
          _funder,
          address(this),
          _oracleFee
      )
    );
    Chainlink.Request memory req = buildChainlinkRequest(jobId, address(this), this.getPriceCallback.selector);
    req.add("get", endpoint);
    req.add("path", path);
    req.addInt("times", 100);
    bytes32 requestId = sendChainlinkRequestTo(oracleAddress, req, _oracleFee);
    requests[requestId] = Request({
      requester: msg.sender,
      payee: _funder,
      tokenId: _tokenId
      });

    return true;

  }

  function getPriceCallback(bytes32 _requestId, uint256 _price)
    public
    recordChainlinkFulfillment(_requestId)
    returns (bool)
  {
    require(
      address(requests[_requestId].requester).call(bytes4(keccak256("_callback(uint256,uint256)")),
      requests[_requestId].tokenId,
      _price
      )
    );
    return true;
  }

  function changeOracleAddress(address _newAddress)
    public
    returns (bool)
  {
    require(msg.sender == owner);
    oracleAddress = _newAddress;
    return true;
  }

  function changeJobId(bytes32 _newJobId)
    public
    returns (bool)
  {
    require(msg.sender == owner);
    jobId = _newJobId;
    return true;
  }

  function changeEndpoint(string _newEndpoint)
    public
    returns (bool)
  {
    require(msg.sender == owner);
    endpoint = _newEndpoint;
    return true;
  }

  function changePath(string _newPath)
    public
    returns (bool)
  {
    require(msg.sender == owner);
    path = _newPath;
    return true;
  }

  function stringToBytes32(string memory source)
    public
    pure
    returns (bytes32 result)
  {
    bytes memory tempEmptyStringTest = bytes(source);
    if (tempEmptyStringTest.length == 0) {
        return 0x0;
    }

    assembly {
        result := mload(add(source, 32))
    }

    return result;
  }

  function kill()
    public
  {
    require(msg.sender == owner);
    selfdestruct(owner);
  }
}
