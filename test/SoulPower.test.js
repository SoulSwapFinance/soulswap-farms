const { assert } = require("chai");

// describe("SoulPower", function() {
//     it("should return the address of SoulPower", async function() {
//       const SoulPower = await ethers.getContractFactory("SoulPower");
//       const soulPower = await SoulPower.deploy();
//       await soulPower.deployed();
  
//       expect(await soulPower.address()).to.equal(address(soulPower));
  
//     });
//   });

describe('SoulPower', function(alice, bob, carol, team, minter) {
    beforeEach(async () => {
        const SoulPower = await ethers.getContractFactory("SoulPower");
        // const soulPower = await SoulPower.deploy();
        this.soul = await SoulPower.new({ from: minter });
    });

    it('mint', async () => {
        await this.soul.mint(alice, 1000, { from: minter });
        assert.equal((await this.soul.balanceOf(alice)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(bob)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(carol)).toString(), '1000');
        assert.equal((await this.soul.balanceOf(team)).toString(), '1000');
    })
});
