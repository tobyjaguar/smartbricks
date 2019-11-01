const SmartBricks = artifacts.require('SmartBricks');
const SmartPiggies = artifacts.require('SmartPiggies');
const StableToken = artifacts.require('StableToken');
const TestnetLINK = artifacts.require('TestnetLINK');
const ResolverSelfReturn = artifacts.require('ResolverSelfReturn');


var dataSource = 'ETHUSD'
var underlying = 'ETH'
var oracleService = 'Self'
var endpoint = 'https://api.coincap.io/v2/assets/ethereum'
var path = ''
var oracleTokenAddress
var oraclePrice = 27000

module.exports = function(deployer) {
  deployer.deploy(SmartBricks, {gas: 8000000, gasPrice: 1100000000, overwrite: false});
  deployer.deploy(SmartPiggies, {gas: 8000000, gasPrice: 1100000000, overwrite: false});
  deployer.deploy(StableToken, {gas: 3000000, gasPrice: 1100000000, overwrite: false});
  deployer.deploy(TestnetLINK, {gas: 3000000, gasPrice: 1100000000, overwrite: false})
  .then(() => {
    return deployer.deploy(ResolverSelfReturn,
        dataSource,
        underlying,
        oracleService,
        endpoint,
        path,
        TestnetLINK.address,
        27000,
        {gas: 3000000, gasPrice: 1100000000, overwrite: false}
      );
  });
};
