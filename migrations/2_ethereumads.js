const EthereumAds = artifacts.require("EthereumAds");
const ChildMintableERC20Upgradeable = artifacts.require("ChildMintableERC20Upgradeable");
const EthereumAdsTokenRewards = artifacts.require("EthereumAdsTokenRewards");
const MockDAIToken = artifacts.require("MockDAIToken");
const EthereumAdsValidatorPools = artifacts.require("EthereumAdsValidatorPools");
const EthereumAdsCampaigns = artifacts.require("EthereumAdsCampaigns");

const { deployProxy } = require('@openzeppelin/truffle-upgrades');

let eadToken, adminAddr, ethereumAdsValidatorPools, eadTokenRewards, daiToken, wethTokenAddr, daiTokenAddr, ethereumAds;

const PRODUCTION = true;

async function stakeValPool(_valPoolAddr, subdomain) {
  await eadToken.approve(ethereumAdsValidatorPools.address, web3.utils.toWei('1000', 'ether'), {from: adminAddr});
  await ethereumAdsValidatorPools.stake(_valPoolAddr, web3.utils.toWei('1000', 'ether'), {from: adminAddr});

  let endpoint;
  if (PRODUCTION) {
    endpoint = "https://"+subdomain+".ethereumads.com";
  } else {
    endpoint = "http://localhost";
  }

  const validatorInfoJSON = JSON.stringify({
    endpoint: endpoint,
    gunPublicKey: "CHlre3ib3kym98kMREZYt9Ufaw6X0XBQR-A6A5y6-2U.b-locsclN4hzuMkbxnm7xEQq4AP8UVyr0fQ4S45KjTs",
    address: _valPoolAddr,
  });
  await ethereumAdsValidatorPools.setValidatorInfoJSON(_valPoolAddr, validatorInfoJSON, {from: adminAddr});
}

module.exports = async function (deployer, network, accounts) {
  let mainnet = false;
  if (network.indexOf('development') != -1) {
    adminAddr = "0x8517d4e020EE8ca93A83F81886122A85E9bb791f"; //mnemonic: runway
  } else {
    adminAddr = "0x181255C7E4D3A6891005f94D1843b8c29D133204"; //mainnet
    mainnet = true;
  }
  console.log('network', network)

  const childChainManagerProxy = "0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa";

  eadToken = await deployProxy(ChildMintableERC20Upgradeable, { deployer, initializer: false });

  if (PRODUCTION) {
    await eadToken.initialize( "EthereumAds", "EAD", 18, childChainManagerProxy, { from: adminAddr});
  } else {
    await eadToken.initialize( "TestCoin", "TST", 18, childChainManagerProxy, { from: adminAddr});
  }

  await eadToken.mint(adminAddr, web3.utils.toWei('10', 'mether'), { from: adminAddr});

  ethereumAds = await deployProxy(EthereumAds, { deployer, initializer:false, unsafeAllowCustomTypes: true });

  const ethereumAdsCampaigns = await deployProxy(EthereumAdsCampaigns, { deployer, initializer: false, unsafeAllowCustomTypes: true }); 
  await ethereumAdsCampaigns.initialize(ethereumAds.address, { from: adminAddr});

  ethereumAdsValidatorPools = await deployProxy(EthereumAdsValidatorPools, { deployer, initializer: false, unsafeAllowCustomTypes: true }); 
  await ethereumAdsValidatorPools.initialize(ethereumAds.address, { from: adminAddr});

  eadTokenRewards = await deployProxy(EthereumAdsTokenRewards, { deployer, initializer: false, unsafeAllowCustomTypes: true }); 
  await eadTokenRewards.initialize(ethereumAds.address, ethereumAdsValidatorPools.address, web3.utils.toWei('100', 'mether'), { from: adminAddr});

  const slashAddr = adminAddr;
  await ethereumAds.initialize(adminAddr, eadToken.address, eadTokenRewards.address, ethereumAdsCampaigns.address, ethereumAdsValidatorPools.address, slashAddr, 10, 10, web3.utils.toWei('1', 'ether'), web3.utils.toWei('3', 'ether'), { from: adminAddr});

  const MINTER_ROLE = await eadToken.MINTER_ROLE(); 
  await eadToken.grantRole(MINTER_ROLE, eadTokenRewards.address, { from: adminAddr});

  // affiliates get 10% of main
  // validator gets 10% of total
  // platform 10% of publisher

  await eadTokenRewards.setupRewardValues([ 
    web3.utils.toWei('630', 'finney'), //campaignOwner
    web3.utils.toWei('70', 'finney'), //campaignAff
    web3.utils.toWei('160', 'finney'), //publisher
    web3.utils.toWei('20', 'finney'), //publisherAff
    web3.utils.toWei('18', 'finney'), //platform
    web3.utils.toWei('2', 'finney'), //platformAff
    web3.utils.toWei('100', 'finney') //validatorPools
  ], { from: adminAddr});
  // sum: 1000

  wethTokenAddr = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"; // POS WETH
  if (mainnet) {
    daiTokenAddr = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063";
  } else {
    daiToken = await deployProxy(MockDAIToken, { deployer, initializer: false, unsafeAllowCustomTypes: true });
    await daiToken.initialize("Mock DAI Token", "MDAI", web3.utils.toWei('100', 'mether'), web3.utils.toWei('100', 'mether'), childChainManagerProxy, { from: adminAddr});
    daiTokenAddr = daiToken.address;
  }

  await ethereumAds.setTokenApproval(daiTokenAddr, web3.utils.toWei('10', 'finney'),true, { from: adminAddr});
  await ethereumAds.setTokenApproval(wethTokenAddr, web3.utils.toWei('10', 'szabo'),true, { from: adminAddr});
  
  if (!mainnet) return;

  const valPool1 = await ethereumAdsValidatorPools.createPool("Validator Pool 1", [adminAddr], { from: adminAddr});
  const valPool2 = await ethereumAdsValidatorPools.createPool("Validator Pool 2", [adminAddr], { from: adminAddr});
  const valPool3 = await ethereumAdsValidatorPools.createPool("Validator Pool 3", [adminAddr], { from: adminAddr});
  const valPool4 = await ethereumAdsValidatorPools.createPool("Validator Pool 4", [adminAddr], { from: adminAddr});

  const val_pool_address1 = valPool1.logs[0].args.pool;
  const val_pool_address2 = valPool2.logs[0].args.pool;
  const val_pool_address3 = valPool3.logs[0].args.pool;
  const val_pool_address4 = valPool4.logs[0].args.pool;

  await stakeValPool(val_pool_address1, "validator1");
  await stakeValPool(val_pool_address2, "validator2");
  await stakeValPool(val_pool_address3, "validator3");
  await stakeValPool(val_pool_address4, "validator4");

  console.log(JSON.stringify({
    ead_address: eadToken.address,
    dai_address: daiTokenAddr,
    val_pool_address1:valPool1.logs[0].args.pool,
    val_pool_address2:valPool2.logs[0].args.pool,
    val_pool_address3:valPool3.logs[0].args.pool,
    val_pool_address4:valPool4.logs[0].args.pool,
    contract_address: ethereumAds.address,
    campaigns_address: ethereumAdsCampaigns.address
  }));
};