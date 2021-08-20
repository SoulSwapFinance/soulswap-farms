const { expect } = require('chai');
const { increaseTime, toWei, fromWei, deployContract } = require('./utils/testHelper.js');


describe('SoulVaultEthers', function () {    
    beforeEach(async () => {
        accounts = await hre.ethers.getSigners()

        soul = await deployContract('MockToken')
        console.log(soul.address)
        seance = await deployContract('MockToken')
        console.log(seance.address)
        summoner = await deployContract('MockSummoner')

        await summoner.initialize(soul.address, seance.address, 0, 100, 50);

        vault = await deployContract('MockVault', soul.address, seance.address, summoner.address)
    });

    describe('deposit', async () => {
        it('transfers soul correctly', async () => {
            soul.connect(accounts[0]).approve(vault.address, toWei(100))
            soul.connect(accounts[0]).mint(toWei(100))

            vault.connect(accounts[0]).deposit(toWei(100))
            const vBal = await soul.balanceOf(vault.address)
            console.log('vault soul bal', fromWei(vBal))

            expect(await soul.balanceOf(accounts[0].address)).to.equal(toWei(100))
            
            // increaseTime(86400)
            // vault.connect(accounts[0]).withdrawAll()
            // expect(await soul.balanceOf(accounts[0].address)).to.equal(toWei(100))

            // const tx = await vault.userInfo(accounts[0].address)
            // expect(tx[0]).to.equal(0)
        });

        // it('receives the right amount of shares for deposit', async () => {

        // });

        // it('receives correct soul amount when multiple people in pool', async () => {

        // });

        // it('receives the correct pending soul rewards', async () => {

        // });
    });

    // describe('withdraw', async () => {
    //     // it('charges fee when withdraw before end period', async () => {

    //     // })

    //     // it('doesnt charge fee when withdraw after end period', async () => {

    //     // })

    //     it('reverts when trying to withdraw funds when has no share balance', async () => {
    //         // expect(await vault.connect(accounts[0]).withdraw(100)).to.be.revertedWith('Nothing to withdraw')
    //     })
    // });

    // describe('compound', async () => {
    //     // it('reinvests available shares when someone uses harvest', async () => {

    //     // })
    // });

    // // describe('check days passed', function() {
    // //     it('should return 1 days passed', async function() {
    // //         increaseTime(86499);
    // //         expect(await sandbox.daysPassed()).to.equal(1);
    // //     });
    // // });

    // // describe('check days passed', function() {
    // //     it('should return 12 days passed', async function() {
    // //         increaseTime(12 * 86400);
    // //         expect(await sandbox.daysPassed()).to.equal(12);
    // //     });
    // // });
    
    // // describe('getSoulPerFantom', function() {
    // //     it('should return soul rate after 2 days passed', async function() {
    // //         increaseTime(2 * 86400);
    // //         expect(await sandbox.getSoulForFtm(1)).to.equal(5);
    // //     });
    // // });

    // // describe('summon souls', function() {
    // //     it('should summon soul to user wallet', async = () => {
    // //         // expect(await sandbox.soulSupply()).to.equal(toWei(34644186));
    // //         // summon 50 souls
    // //         // const summonSoulsTx = await sandbox.summonSouls(toWei(50), { value: toWei(50)});
    // //         const summonSoulsTx = await sandbox.summonSouls( toWei(50), { value: toWei(10) });
    // //         await summonSoulsTx.wait();
    // //         expect(await sandbox.soulSupply()).to.equal(toWei(10000 - 50));
    // //     });
    // // });

});