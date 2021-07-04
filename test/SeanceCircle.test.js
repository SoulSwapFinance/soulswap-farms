const { advanceBlockTo } = require('@openzeppelin/test-helpers/src/time');
const { assert } = require('chai');
const SoulToken = artifacts.require('SoulToken');
const SeanceCircle = artifacts.require('SeanceCircle');

contract('SeanceCircle', ([alice, bob, carol, dev, minter]) => {
  beforeEach(async () => {
    this.soul = await SoulToken.new({ from: minter });
    this.seance = await SeanceCircle.new(this.soul.address, { from: minter });
  });

  it('mint', async () => {
    await this.seance.mint(alice, 1000, { from: minter });
    assert.equal((await this.seance.balanceOf(alice)).toString(), '1000');
  });

  it('burn', async () => {
    await advanceBlockTo('650');
    await this.seance.mint(alice, 1000, { from: minter });
    await this.seance.mint(bob, 1000, { from: minter });
    assert.equal((await this.seance.totalSupply()).toString(), '2000');
    await this.seance.burn(alice, 200, { from: minter });

    assert.equal((await this.seance.balanceOf(alice)).toString(), '800');
    assert.equal((await this.seance.totalSupply()).toString(), '1800');
  });

  it('safeSoulTransfer', async () => {
    assert.equal(
      (await this.soul.balanceOf(this.seance.address)).toString(),
      '0'
    );
    await this.soul.mint(this.seance.address, 1000, { from: minter });
    await this.seance.safeSoulTransfer(bob, 200, { from: minter });
    assert.equal((await this.soul.balanceOf(bob)).toString(), '200');
    assert.equal(
      (await this.soul.balanceOf(this.seance.address)).toString(),
      '800'
    );
    await this.seance.safeSoulTransfer(bob, 2000, { from: minter });
    assert.equal((await this.soul.balanceOf(bob)).toString(), '1000');
  });
});
