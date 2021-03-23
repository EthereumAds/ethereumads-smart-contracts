const EthereumAdsCampaigns = artifacts.require("EthereumAdsCampaigns");
const { round, advanceTime, prerequisites, showBalances, stakeValPool } = require("./helpers");
const keccak = require("keccak256");
const BN = require('bn.js');
var chai = require('chai').use(require('chai-as-promised'));
var should = chai.should();

let ethereumAds, ethereumAdsValidatorPools, daiToken, eadToken, daiAddr, accs;

contract("EthereumAds", accounts => {

    before(async function () {
        [ethereumAds, ethereumAdsValidatorPools, eadToken, daiToken, daiAddr, accs] = await prerequisites(accounts);
    });

    it("should setup 4 and stake 2 validators", async () => {
        accs.valPoolAddr1 = (await ethereumAdsValidatorPools.createPool("Test Pool 1", [accs.validatorAddr1])).logs[0].args.pool.toString();
        accs.valPoolAddr2 = (await ethereumAdsValidatorPools.createPool("Test Pool 2", [accs.validatorAddr2])).logs[0].args.pool.toString();
        accs.valPoolAddr3 = (await ethereumAdsValidatorPools.createPool("Test Pool 3", [accs.validatorAddr3])).logs[0].args.pool.toString();
        accs.valPoolAddr4 = (await ethereumAdsValidatorPools.createPool("Test Pool 4", [accs.validatorAddr4])).logs[0].args.pool.toString();

        await stakeValPool(accs.valPoolAddr1, accs.validatorAddr1);
        await stakeValPool(accs.valPoolAddr2, accs.validatorAddr2);
        await stakeValPool(accs.valPoolAddr3, accs.validatorAddr3);
        await stakeValPool(accs.valPoolAddr4, accs.validatorAddr4);
    });

    it("should create campaign and approve funds", async () => {
        const advertiserAffiliateName = "";
        const ethereumAdsCampaigns = await EthereumAdsCampaigns.deployed();

        let advertiserAffiliate;
        if (!advertiserAffiliateName) {
            advertiserAffiliate = accs.zeroAddr;
        } else {
            advertiserAffiliate = ethereumAds.affiliates(advertiserAffiliate);
        }
        // rate limited to 10 clicks in 1 hour
        const campaignTx = await ethereumAdsCampaigns.createCampaign(web3.utils.toWei('1', 'ether'), 3600, 10, daiAddr, advertiserAffiliate, "BANNER", accs.zeroAddr, { from: accs.advertiserAddr });
        accs.campaignAddr = campaignTx.logs[0].args.campaign.toString();

        await daiToken.approve(ethereumAdsCampaigns.address, web3.utils.toWei('5', 'ether'), { from: accs.advertiserAddr });

        const valPools1 = await ethereumAds.getValidatorSubSetInfo(accs.publisherAddr);
        const valPools2 = await ethereumAds.getValidatorSubSetInfo(accs.advertiserAddr);
        console.log('valpools1', valPools1, valPools2);
        /*
            '{"endpoint":"endpoint","gunPublicKey":"","address":"4"}',
            '{"endpoint":"endpoint","gunPublicKey":"","address":"2"}',
            '{"endpoint":"endpoint","gunPublicKey":"","address":"2"}',
            '{"endpoint":"endpoint","gunPublicKey":"","address":"1"}'
        */
    });

    let pcArgs, rewardable = true;
    it("should process click without payment after first validation", async () => {
        pcArgs = [accs.zeroAddr, "", accs.publisherAddr, "", accs.campaignAddr];
        accs.publisherBal1 = await daiToken.balanceOf(accs.publisherAddr);

        console.log('pooladdr', accs.valPoolAddr1);
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr1, "CLICKDATA", keccak("IPDATA"), rewardable, true, { from: accs.validatorAddr1 });
        accs.publisherBal2 = await daiToken.balanceOf(accs.publisherAddr);

        assert.equal(round(accs.publisherBal1), round(accs.publisherBal2), "No payment after 1 validation");
    });

    it("should process click and payment after second validation", async () => {
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr2, "CLICKDATA", keccak("IPDATA"), rewardable, true, { from: accs.validatorAddr2 });
        accs.publisherBal3 = await daiToken.balanceOf(accs.publisherAddr);
        assert.notEqual(round(accs.publisherBal1), round(accs.publisherBal3), "Payment after 2 validations");
    });

    it("should process click from different ip", async () => {
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr1, "CLICKDATA2", keccak("IPDATA2"), rewardable, true, { from: accs.validatorAddr1 });
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr2, "CLICKDATA2", keccak("IPDATA2"), rewardable, true, { from: accs.validatorAddr2 });
        accs.publisherBal4 = await daiToken.balanceOf(accs.publisherAddr);
        assert.notEqual(round(accs.publisherBal3), round(accs.publisherBal4), "Payment after 2 validations");
    });

    it("should not pay for duplicate clicks from same ip", async () => {
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr1, "CLICKDATA", keccak("IPDATA"), rewardable, true, { from: accs.validatorAddr1 });
        await ethereumAds.processClickWithAffiliateNames(...pcArgs, accs.zeroAddr, accs.valPoolAddr2, "CLICKDATA", keccak("IPDATA"), rewardable, true, { from: accs.validatorAddr2 });
        accs.publisherBal5 = await daiToken.balanceOf(accs.publisherAddr);
        assert.equal(round(accs.publisherBal4), round(accs.publisherBal5), "No additional payments");
    });

    it("should only be possible for EthereumAds contract to mint EAD", async () => {
        return eadToken.mint(accs.advertiserAddr, 10000, { from: accs.validatorAddr1 }).should.be.rejected;
    });

    it("should setup slasher role", async () => {
        const SLASHER_ROLE = await ethereumAdsValidatorPools.SLASHER_ROLE();
        await ethereumAdsValidatorPools.grantRole(SLASHER_ROLE, accs.adminAddr, { from: accs.adminAddr });
    });

    it("should transfer EAD tokens to delegates", async () => {
        await eadToken.transfer(accs.delegateAddr1, web3.utils.toWei('10000', 'ether'), { from: accs.adminAddr });
        await eadToken.transfer(accs.delegateAddr2, web3.utils.toWei('10000', 'ether'), { from: accs.adminAddr });
        await eadToken.transfer(accs.delegateAddr3, web3.utils.toWei('10000', 'ether'), { from: accs.adminAddr });
        await eadToken.transfer(accs.delegateAddr4, web3.utils.toWei('10000', 'ether'), { from: accs.adminAddr });
    });

    let stakeAmount;
    it("should stake EAD tokens", async () => {
        accs.delegateBal1_t1 = (await eadToken.balanceOf(accs.delegateAddr1));

        stakeAmount = web3.utils.toWei('100', 'ether');
        await eadToken.approve(ethereumAdsValidatorPools.address, stakeAmount, { from: accs.delegateAddr1 });
        await ethereumAdsValidatorPools.stake(accs.valPoolAddr1, stakeAmount, { from: accs.delegateAddr1 });

        accs.delegateBal1_t2 = (await eadToken.balanceOf(accs.delegateAddr1));
        assert.notEqual(round(accs.delegateBal1_t1), round(accs.delegateBal1_t2), "Did not stake");
    });

    it("should slash 20% of tokens", async () => {
        const valPoolBal1 = (await ethereumAdsValidatorPools.eadTotalSupply(accs.valPoolAddr1));
        const slashAmount = valPoolBal1.mul(new BN(20)).div(new BN(100)).toString();
        await ethereumAdsValidatorPools.slash(accs.valPoolAddr1, slashAmount);
    });

    it("should give staker 80% of his stake back after unstaking", async () => {
        await ethereumAdsValidatorPools.requestUnlock(accs.valPoolAddr1, { from: accs.delegateAddr1 });
        await advanceTime(3600 * 24 * 31);
        await ethereumAdsValidatorPools.unstake(accs.valPoolAddr1, { from: accs.delegateAddr1 });

        accs.delegateBal1_t3 = (await eadToken.balanceOf(accs.delegateAddr1));
        assert.equal(round(accs.delegateBal1_t1.sub(accs.delegateBal1_t3)), round(new BN(stakeAmount).mul(new BN(20)).div(new BN(100))), "Not received 80 percent stake back");
    });

    after(async function () {
        await showBalances();
    })
});