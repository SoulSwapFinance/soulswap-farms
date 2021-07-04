const { assert } = require("chai");

const SoulToken = artifacts.require('SoulToken');

contract('SoulToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.soul = await SoulToken.new({ from: minter });
    });


    it('mint', async () => {
        await this.soul.mint(alice, 1000, { from: minter });
        assert.equal((await this.soul.balanceOf(alice)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(bob)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(carol)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(dev)).toString(), '1000');
    })
});
