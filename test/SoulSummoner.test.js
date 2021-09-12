const { expect } = require('chai');
const { increaseTime, toWei, fromWei, deployContract } = require('./utils/testHelper.js');

describe('SoulSummoner', (alice, bob, team, dao, minter) => {
  const ethers = hre.ethers;
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d';

  beforeEach(async () => {
    const SoulPower = await ethers.getContractFactory("MockSoulPower");
    const SeanceCircle = await ethers.getContractFactory("MockSeanceCircle");
    const SoulSummoner = await ethers.getContractFactory("MockSoulSummoner");
    const LPToken = await ethers.getContractFactory("MockERC20");

    const soul = await SoulPower.deploy();
    await soul.deployed();
    
    const seance = await SeanceCircle.deploy();
    await seance.deployed();

    const summoner = await SoulSummoner.deploy();
    await summoner.deployed();
    
    await seance.initialize(soul.address);    
    await soul.grantRole(THOTH, summoner.address);
    ///

    await this.lp1.transfer(bob, '2000')
    await this.lp2.transfer(bob, '2000')
    await this.lp3.transfer(bob, '2000')

    await this.lp1.transfer(alice, '2000')
    await this.lp2.transfer(alice, '2000')
      await this.lp3.transfer(alice, '2000')
  });

    it('real case', async () => {
      this.lp4 = await MockERC20.new('LPToken', 'LP1', '1000000')
      this.lp5 = await MockERC20.new('LPToken', 'LP2', '1000000')
      this.lp6 = await MockERC20.new('LPToken', 'LP3', '1000000')
      this.lp7 = await MockERC20.new('LPToken', 'LP1', '1000000')
      this.lp8 = await MockERC20.new('LPToken', 'LP2', '1000000')
      this.lp9 = await MockERC20.new('LPToken', 'LP3', '1000000')
      await this.summoner.add('2000', this.lp1.address, true)
      await this.summoner.add('1000', this.lp2.address, true)
      await this.summoner.add('500', this.lp3.address, true)
      await this.summoner.add('500', this.lp3.address, true)
      await this.summoner.add('500', this.lp3.address, true)
      await this.summoner.add('500', this.lp3.address, true)
      await this.summoner.add('500', this.lp3.address, true)
      await this.summoner.add('100', this.lp3.address, true)
      await this.summoner.add('100', this.lp3.address, true)
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
      await this.summoner.add('1000', this.lp1.address, true)
      await this.summoner.add('1000', this.lp2.address, true)
      await this.summoner.add('1000', this.lp3.address, true)

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
      await this.summoner.add('1000', this.lp1.address, true)
      await this.summoner.add('1000', this.lp2.address, true)
      await this.summoner.add('1000', this.lp3.address, true)

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
      await this.summoner.add('1000', this.lp1.address, true)
      await this.summoner.add('1000', this.lp2.address, true)
      await this.summoner.add('1000', this.lp3.address, true)

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

      await this.summoner.updateMultiplier('0')

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
