const EthereumAds = artifacts.require("EthereumAds");
const EthereumAdsValidatorPools = artifacts.require("EthereumAdsValidatorPools");
const EADToken = artifacts.require("ChildMintableERC20Upgradeable");
const MockDAIToken = artifacts.require("MockDAIToken");
const BN = require('bn.js');
const SCALAR = new BN("100");
const isTestnet = true;
let daiToken, eadToken, ethereumAds, accounts, accs;

function round(x) {
    if (!BN.isBN(x)) {
        x = new BN(x);
    }
    return x.div(SCALAR).mul(SCALAR).toString();
}

function advanceTime(time) {
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
            jsonrpc: '2.0',
            method: 'evm_increaseTime',
            params: [time],
            id: new Date().getTime()
        }, (err, result) => {
            if (err) { return reject(err) }
            return resolve(result)
        })
    });
}

function getAccObj(_accounts) {
    return {
        adminAddr: _accounts[0],
        advertiserAddr: _accounts[1],
        publisherAddr: _accounts[2],
        publisherAffiliateAddr: _accounts[3],
        advertiserAffiliateAddr: _accounts[4],
        validatorAddr1: _accounts[5],
        validatorAddr2: _accounts[6],
        validatorAddr3: _accounts[7],
        validatorAddr4: _accounts[8],
        delegateAddr1: _accounts[9],
        delegateAddr2: _accounts[10],
        delegateAddr3: _accounts[11],
        delegateAddr4: _accounts[12],
        zeroAddr: "0x0000000000000000000000000000000000000000",
        names: ["admin", "advertiser", "publisher", "publisherAffiliate", "advertiserAffiliate", "validator1", "validator2", "validator3", "validator4"]
    };
}

async function prerequisites(_accounts) {
    accounts = _accounts;
    accs = getAccObj(_accounts);

    accs.adminAddr = accounts[0];
    accs.advertiserAddr = accounts[1];

    ethereumAds = await EthereumAds.deployed();

    if (isTestnet) {
        daiToken = await MockDAIToken.deployed();
        daiAddr = daiToken.address;
        await daiToken.transfer(accs.advertiserAddr, web3.utils.toWei('10', 'ether'), { from: accs.adminAddr });
    } else {
        daiAddr = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063" //matic mainnet
    }

    const eadAddr = await ethereumAds.eadAddr();
    eadToken = await EADToken.at(eadAddr);

    const ethereumAdsValidatorPools = await EthereumAdsValidatorPools.deployed();

    return [ethereumAds, ethereumAdsValidatorPools, eadToken, daiToken, daiAddr, accs];
}

async function showBalances(onlyName = "", caption = "") {
    if (caption) {
        console.log("showbalances after " + caption)
    }

    const bal = {};
    let i;
    for (i = 0; i < accounts.length; i++) {
        if (!accs.names[i]) break;
        bal[i] = {};
        bal[i]._name = accs.names[i];
        bal[i].dai = (await daiToken.balanceOf(accounts[i])).toString();
        bal[i].ead = (await eadToken.balanceOf(accounts[i])).toString();
    }

    try {
        i++;
        bal[i] = {};
        bal[i]._name = "validatorPool1";
        bal[i].dai = (await daiToken.balanceOf(valPoolAddr1)).toString();
        bal[i].ead = (await eadToken.balanceOf(valPoolAddr1)).toString();

        i++;
        bal[i] = {};
        bal[i]._name = "validatorPool2";
        bal[i].dai = (await daiToken.balanceOf(valPoolAddr2)).toString();
        bal[i].ead = (await eadToken.balanceOf(valPoolAddr2)).toString();

        i++;
        bal[i] = {};
        bal[i]._name = "validatorPool3";
        bal[i].dai = (await daiToken.balanceOf(valPoolAddr3)).toString();
        bal[i].ead = (await eadToken.balanceOf(valPoolAddr3)).toString();

        i++;
        bal[i] = {};
        bal[i]._name = "validatorPool4";
        bal[i].dai = (await daiToken.balanceOf(valPoolAddr4)).toString();
        bal[i].ead = (await eadToken.balanceOf(valPoolAddr4)).toString();

    } catch (err) { }

    if (onlyName == "") {
        console.log("bals", bal);
    } else {
        for (let k in bal) {
            if (bal[k]._name == onlyName) {
                console.log(bal[k]);
            }
        }
    }
}

async function stakeValPool(_valPoolAddr, _validatorAddr) {
    const ethereumAdsValidatorPools = await EthereumAdsValidatorPools.deployed();
    await eadToken.approve(ethereumAdsValidatorPools.address, web3.utils.toWei('10', 'ether'), { from: accs.adminAddr });
    await ethereumAdsValidatorPools.stake(_valPoolAddr, web3.utils.toWei('10', 'ether'), { from: accs.adminAddr });

    const validatorInfoJSON = JSON.stringify({
        endpoint: "endpoint",
        gunPublicKey: "",
        address: _valPoolAddr,
    });
    await ethereumAdsValidatorPools.setValidatorInfoJSON(_valPoolAddr, validatorInfoJSON, { from: _validatorAddr });
}

module.exports = { round, advanceTime, prerequisites, showBalances, stakeValPool };