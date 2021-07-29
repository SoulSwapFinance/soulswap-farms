const { expectRevert, time } = require('@openzeppelin/test-helpers');
// const { BigNumber } = require('ethers');
// const SoulPower = artifacts.require('SoulPower');
// const SeanceCircle = artifacts.require('SeanceCircle');
// const SoulSummoner = artifacts.require('SoulSummoner');
// const MockERC20 = artifacts.require('libs/MockERC20');

// const SoulPower = require('./SoulPower.test');
// const SeanceCircle = require('./SeanceCircle.test');

describe("SoulPower", function() {
    it("should return the address of SoulPower", async function() {
      const SoulPower = await ethers.getContractFactory("SoulPower");
      const soulPower = await SoulPower.deploy();
      await soulPower.deployed();
  
      expect(await address(address)).to.equal(address(soulPower));
  
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

describe('SoulSummoner', function(alice, bob, team, treasury, minter) {
    beforeEach(async () => {
        this.soul = await soulPower.new({ from: minter });
        this.seance = await SeanceCircle.new(this.soul.address, { from: minter });
        this.lp1 = await MockERC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp2 = await MockERC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockERC20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.summoner = await SoulSummoner.new(this.soul.address, this.seance.address, team, treasury, await time.latest(), { from: minter });
        await this.soul.transferOwnership(this.summoner.address, { from: minter });
        await this.seance.transferOwnership(this.summoner.address, { from: minter });

        await this.lp1.transfer(bob, '2000', { from: minter });
        await this.lp2.transfer(bob, '2000', { from: minter });
        await this.lp3.transfer(bob, '2000', { from: minter });

        await this.lp1.transfer(alice, '2000', { from: minter });
        await this.lp2.transfer(alice, '2000', { from: minter });
        await this.lp3.transfer(alice, '2000', { from: minter });
    });
    it('real case', async () => {
      this.lp4 = await MockERC20.new('LPToken', 'LP1', '1000000', { from: minter });
      this.lp5 = await MockERC20.new('LPToken', 'LP2', '1000000', { from: minter });
      this.lp6 = await MockERC20.new('LPToken', 'LP3', '1000000', { from: minter });
      this.lp7 = await MockERC20.new('LPToken', 'LP1', '1000000', { from: minter });
      this.lp8 = await MockERC20.new('LPToken', 'LP2', '1000000', { from: minter });
      this.lp9 = await MockERC20.new('LPToken', 'LP3', '1000000', { from: minter });
      await this.summoner.add('2000', this.lp1.address, true, { from: minter });
      await this.summoner.add('1000', this.lp2.address, true, { from: minter });
      await this.summoner.add('500', this.lp3.address, true, { from: minter });
      await this.summoner.add('500', this.lp3.address, true, { from: minter });
      await this.summoner.add('500', this.lp3.address, true, { from: minter });
      await this.summoner.add('500', this.lp3.address, true, { from: minter });
      await this.summoner.add('500', this.lp3.address, true, { from: minter });
      await this.summoner.add('100', this.lp3.address, true, { from: minter });
      await this.summoner.add('100', this.lp3.address, true, { from: minter });
      assert.equal((await this.summoner.poolLength()).toString(), "10");

      await time.increase('70');
      await this.lp1.approve(this.summoner.address, '1000', { from: alice });
      assert.equal((await this.soul.balanceOf(alice)).toString(), '0');
      await this.summoner.deposit(1, '20', { from: alice });
      await this.summoner.withdraw(1, '20', { from: alice });
      assert.equal((await this.soul.balanceOf(alice)).toString(), '63');

      await this.soul.approve(this.summoner.address, '1000', { from: alice });
      await this.summoner.enterStaking('20', { from: alice });
      await this.summoner.enterStaking('0', { from: alice });
      await this.summoner.enterStaking('0', { from: alice });
      await this.summoner.enterStaking('0', { from: alice });
      assert.equal((await this.soul.balanceOf(alice)).toString(), '993');
      assert.equal((await this.soul.balanceOf(team)).toString(), '114');

    })


    it('deposit/withdraw', async () => {
      await this.summoner.add('1000', this.lp1.address, true, { from: minter });
      await this.summoner.add('1000', this.lp2.address, true, { from: minter });
      await this.summoner.add('1000', this.lp3.address, true, { from: minter });

      await this.lp1.approve(this.summoner.address, '100', { from: alice });
      await this.summoner.deposit(1, '20', { from: alice });
      await this.summoner.deposit(1, '0', { from: alice });
      await this.summoner.deposit(1, '40', { from: alice });
      await this.summoner.deposit(1, '0', { from: alice });
      assert.equal((await this.lp1.balanceOf(alice)).toString(), '1940');
      await this.summoner.withdraw(1, '10', { from: alice });
      assert.equal((await this.lp1.balanceOf(alice)).toString(), '1950');
      assert.equal((await this.soul.balanceOf(alice)).toString(), '999');
      assert.equal((await this.soul.balanceOf(team)).toString(), '112');

      
      await this.lp1.approve(this.summoner.address, '100', { from: bob });
      assert.equal((await this.lp1.balanceOf(bob)).toString(), '2000');
      await this.summoner.deposit(1, '50', { from: bob });
      assert.equal((await this.lp1.balanceOf(bob)).toString(), '1950');
      await this.summoner.deposit(1, '0', { from: bob });
      assert.equal((await this.soul.balanceOf(bob)).toString(), '125');
    })

    it('staking/unstaking', async () => {
      await this.summoner.add('1000', this.lp1.address, true, { from: minter });
      await this.summoner.add('1000', this.lp2.address, true, { from: minter });
      await this.summoner.add('1000', this.lp3.address, true, { from: minter });

      await this.lp1.approve(this.summoner.address, '10', { from: alice });
      await this.summoner.deposit(1, '2', { from: alice }); //0
      await this.summoner.withdraw(1, '2', { from: alice }); //1

      await this.soul.approve(this.summoner.address, '250', { from: alice });
      await this.summoner.enterStaking('240', { from: alice }); //3
      assert.equal((await this.seance.balanceOf(alice)).toString(), '240');
      assert.equal((await this.soul.balanceOf(alice)).toString(), '10');
      await this.summoner.enterStaking('10', { from: alice }); //4
      assert.equal((await this.seance.balanceOf(alice)).toString(), '250');
      assert.equal((await this.soul.balanceOf(alice)).toString(), '249');
      await this.summoner.leaveStaking(250);
      assert.equal((await this.seance.balanceOf(alice)).toString(), '0');
      assert.equal((await this.soul.balanceOf(alice)).toString(), '749');

    });


    it('update multiplier', async () => {
      await this.summoner.add('1000', this.lp1.address, true, { from: minter });
      await this.summoner.add('1000', this.lp2.address, true, { from: minter });
      await this.summoner.add('1000', this.lp3.address, true, { from: minter });

      await this.lp1.approve(this.summoner.address, '100', { from: alice });
      await this.lp1.approve(this.summoner.address, '100', { from: bob });
      await this.summoner.deposit(1, '100', { from: alice });
      await this.summoner.deposit(1, '100', { from: bob });
      await this.summoner.deposit(1, '0', { from: alice });
      await this.summoner.deposit(1, '0', { from: bob });

      await this.soul.approve(this.summoner.address, '100', { from: alice });
      await this.soul.approve(this.summoner.address, '100', { from: bob });
      await this.summoner.enterStaking('50', { from: alice });
      await this.summoner.enterStaking('100', { from: bob });

      await this.summoner.updateMultiplier('0', { from: minter });

      await this.summoner.enterStaking('0', { from: alice });
      await this.summoner.enterStaking('0', { from: bob });
      await this.summoner.deposit(1, '0', { from: alice });
      await this.summoner.deposit(1, '0', { from: bob });

      assert.equal((await this.soul.balanceOf(alice)).toString(), '54491');
      assert.equal((await this.soul.balanceOf(bob)).toString(), '150858');

      await time.increase('50');

      await this.summoner.enterStaking('0', { from: alice });
      await this.summoner.enterStaking('0', { from: bob });
      await this.summoner.deposit(1, '0', { from: alice });
      await this.summoner.deposit(1, '0', { from: bob });

      assert.equal((await this.soul.balanceOf(alice)).toString(), '164158');
      assert.equal((await this.soul.balanceOf(bob)).toString(), '306816');

      await this.summoner.leaveStaking('50', { from: alice });
      await this.summoner.leaveStaking('100', { from: bob });
      await this.summoner.withdraw(1, '100', { from: alice });
      await this.summoner.withdraw(1, '100', { from: bob });

    });

    it('should allow team and only team to update team', async () => {
        assert.equal((await this.summoner.team()).valueOf(), team);
        await expectRevert(this.summoner.newTeam(bob, { from: bob }), 'team: le who are you?');
        await this.summoner.newTeam(bob, { from: team });
        assert.equal((await this.summoner.team()).valueOf(), bob);
        await this.summoner.newTeam(alice, { from: bob });
        assert.equal((await this.summoner.team()).valueOf(), alice);
    })
});
