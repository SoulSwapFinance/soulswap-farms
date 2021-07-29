const { time } = require('@openzeppelin/test-helpers');
const { BigNumber } = require('ethers');

// const SoulPower = artifacts.require('SoulPower');
// const SeanceCircle = artifacts.require('SeanceCircle');
// const SoulSummoner = artifacts.require('SoulSummoner');
// const SoulVault = artifacts.require('SoulVault');
// const MockERC20 = artifacts.require('libs/MockERC20');

// const SoulPower = require('./SoulPower.test');
// const SeanceCircle = require('./SeanceCircle.test');

describe("SoulPower", function() {
    it("should return the address of SoulPower", async function() {
      const SoulPower = await ethers.getContractFactory("SoulPower");
      const soulPower = await SoulPower.deploy();
      await soulPower.deployed();
  
      expect(await soulPower.address()).to.equal(address(soulPower));
  
    });
  });

describe("SeanceCircle", function() {
  it("should return the address of SoulPower", async function() {
    const SeanceCircle = await ethers.getContractFactory("SeanceCircle");
    const seanceCircle = await SeanceCircle.deploy();
    await seanceCircle.deployed();

    expect(await seanceCircle.address()).to.equal(address(seanceCircle));

  });
});

describe('SoulVault', function(alice, bob, team, treasury, minter) {
    beforeEach(async () => {

        this.soul; // = await soul.new({ from: minter });
        this.seance; // = await seance.new(this.soul.address, { from: minter });
        this.lp1 = await MockERC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp2 = await MockERC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockERC20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.summoner = await SoulSummoner.new(this.soul.address, this.seance.address, team, treasury, await time.latest(), { from: minter });

        await this.soul.mint(alice, '2000', { from: minter });
        await this.soul.mint(bob, '2000', { from: minter });

        await this.soul.transferOwnership(this.summoner.address, { from: minter });
        await this.seance.transferOwnership(this.summoner.address, { from: minter });
        
        this.vault = await SoulVault.new(this.soul.address, this.seance.address, this.summoner.address, team, treasury, { from: minter });
    });

    it('staking deposit & withdraw', async () => {
        await this.soul.approve(this.vault.address, '1000', { from: alice });
        expect((await this.vault.balanceOf()).toString()).to.equal('0');
        expect((await this.soul.balanceOf(alice)).toString()).to.equal('2000');
        await this.vault.deposit('1000', { from: alice });
        expect((await this.vault.balanceOf()).toString()).to.equal('1000');
        expect((await this.soul.balanceOf(alice)).toString()).to.equal('1000');

        expect((await this.summoner.pendingSoul(0, this.vault.address)).toString()).to.equal('0');

        console.log(BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).toNumber())
        await ethers.provider.send("evm_increaseTime", [60])  // fast forward 
        await ethers.provider.send("evm_mine", [])  // mine the block to set the block.timestamp
        console.log(BigNumber.from((await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp).toNumber())

        expect((await this.summoner.pendingSoul(0, this.vault.address)).toString()).to.equal('173611111111111111080');
        console.log('SoulVault`s new SOUL balance: '+await this.summoner.pendingSoul(0, this.vault.address) / (10 ** 18))



    })
});
