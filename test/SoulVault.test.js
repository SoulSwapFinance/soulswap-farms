const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { BigNumber } = require('ethers');

const SoulPower = artifacts.require('SoulPower');
const SeanceCircle = artifacts.require('SeanceCircle');
const SoulSummoner = artifacts.require('SoulSummoner');
const SoulVault = artifacts.require('SoulVault');
const MockERC20 = artifacts.require('libs/MockERC20');

contract('SoulVault', ([alice, bob, team, treasury, minter]) => {
    beforeEach(async () => {
        this.soul = await SoulPower.new({ from: minter });
        this.seance = await SeanceCircle.new(this.soul.address, { from: minter });
        this.lp1 = await MockERC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp2 = await MockERC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockERC20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.chef = await SoulSummoner.new(this.soul.address, this.seance.address, team, treasury, await time.latest(), { from: minter });

        await this.soul.mint(alice, '2000', { from: minter });
        await this.soul.mint(bob, '2000', { from: minter });

        await this.soul.transferOwnership(this.chef.address, { from: minter });
        await this.seance.transferOwnership(this.chef.address, { from: minter });
        
        this.vault = await SoulVault.new(this.soul.address, this.seance.address, this.chef.address, team, treasury, { from: minter });
    });

    it('staking deposit & withdraw', async () => {
        await this.soul.approve(this.vault.address, '1000', { from: alice });
        expect((await this.vault.balanceOf()).toString()).to.equal('0');
        expect((await this.soul.balanceOf(alice)).toString()).to.equal('2000');
        await this.vault.deposit('1000', { from: alice });
        expect((await this.vault.balanceOf()).toString()).to.equal('1000');
        expect((await this.soul.balanceOf(alice)).toString()).to.equal('1000');

        expect((await this.chef.pendingSoul(0, this.vault.address)).toString()).to.equal('0');

        console.log(BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).toNumber())
        await ethers.provider.send("evm_increaseTime", [60])  // fast forward 
        await ethers.provider.send("evm_mine", [])  // mine the block to set the block.timestamp
        console.log(BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).toNumber())

        expect((await this.chef.pendingSoul(0, this.vault.address)).toString()).to.equal('173611111111111111080');
        console.log('SoulVault`s new SOUL balance: '+await this.chef.pendingSoul(0, this.vault.address) / (10 ** 18))



    })
});
