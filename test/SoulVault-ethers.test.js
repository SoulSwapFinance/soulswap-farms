const { expect } = require('chai');
const { increaseTime, toWei, deployContract } = require('./utils/testHelper.js');

describe('SoulVaultEthers', () => {
    const ethers = hre.ethers;

    beforeEach(async () => {
        soul = await deployContract('MockToken')
        seance = await deployContract('MockToken')
        summoner = await deployContract('MockSummoner')

        await summoner.initialize(soul.address, seance.address, 0, 100, 50);

        vault = await deployContract('MockVault', soul.address, seance.address, summoner.address)
    });

    describe('deposit', function() {
        it('deposits correctly', async () => {
            await soul.mint(toWei(100))
            await soul.approve(vault.address, toWei(100))

            await vault.deposit(toWei(100))
            // expect(await vault.soul()).to.equal(soul);
        });
    });

    // describe('check days passed', function() {
    //     it('should return 1 days passed', async function() {
    //         increaseTime(86499);
    //         expect(await sandbox.daysPassed()).to.equal(1);
    //     });
    // });

    // describe('check days passed', function() {
    //     it('should return 12 days passed', async function() {
    //         increaseTime(12 * 86400);
    //         expect(await sandbox.daysPassed()).to.equal(12);
    //     });
    // });
    
    // describe('getSoulPerFantom', function() {
    //     it('should return soul rate after 2 days passed', async function() {
    //         increaseTime(2 * 86400);
    //         expect(await sandbox.getSoulForFtm(1)).to.equal(5);
    //     });
    // });

    // describe('summon souls', function() {
    //     it('should summon soul to user wallet', async = () => {
    //         // expect(await sandbox.soulSupply()).to.equal(toWei(34644186));
    //         // summon 50 souls
    //         // const summonSoulsTx = await sandbox.summonSouls(toWei(50), { value: toWei(50)});
    //         const summonSoulsTx = await sandbox.summonSouls( toWei(50), { value: toWei(10) });
    //         await summonSoulsTx.wait();
    //         expect(await sandbox.soulSupply()).to.equal(toWei(10000 - 50));
    //     });
    // });

});