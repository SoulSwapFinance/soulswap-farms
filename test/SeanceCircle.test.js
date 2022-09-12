// const { advanceBlockTo } = require('@openzeppelin/test-helpers/src/time');
// const address = require('@openzeppelin/test-helpers');
// const { assert, expect } = require('chai');

// describe("SoulPower", function() {
//   it("should return the address of SoulPower", async function() {
//     const SoulPower = await ethers.getContractFactory("SoulPower");
//     const soul = await SoulPower.deploy();
//     await soul.deployed();

//     expect(await soul.address).to.equal(soul.address);

//   });
// });

// // describe("SeanceCircle", function() {
// //   it("should return the address of SeanceCircle", async function() {
// //     const SeanceCircle = await ethers.getContractFactory("SeanceCircle");
// //     const seance = await SeanceCircle.deploy();
// //     await seance.deployed();

// //     expect(await seance.address).to.equal(seance.address);
// //   });
// // });

// // const SeanceCircle = await ethers.getContractFactory("SeanceCircle");
// // const SoulPower = artifacts.require('SoulPower');
// // const SeanceCircle = artifacts.require('SeanceCircle');

// describe('SeanceCircle', function(alice, bob, minter) {
//   beforeEach(async function() {
//     const SoulPower = await ethers.getContractFactory("SoulPower");
//     const soul = await SoulPower.deploy();
//     this.soul = await soul.deployed();

//     const SeanceCircle = await ethers.getContractFactory("SeanceCircle");
//     const seance = await SeanceCircle.deploy();
//     this.seance = await seance.deployed();

//     // this.soul = await soul.new({ from: minter });
//     // this.seance = await seance.deploy(this.soul.address, { from: minter });

//     expect(await seance.address).to.equal(seance.address);

//   });

//   it('mint', async function() {
//     await this.seance.initialize(await this.soul.address);
//     await this.seance.mint(alice, 1000);
//     assert.equal((await this.seance.balanceOf(alice)).toString(), '1000');
//   });

//   it('burn', async function() {
//     await advanceBlockTo('650');
//     await this.seance.mint(alice, 1000, { from: minter });
//     await this.seance.mint(bob, 1000, { from: minter });
//     assert.equal((await this.seance.totalSupply()).toString(), '2000');
//     await this.seance.burn(alice, 200, { from: minter });

//     assert.equal((await this.seance.balanceOf(alice)).toString(), '800');
//     assert.equal((await this.seance.totalSupply()).toString(), '1800');
//   });

//   it('safeSoulTransfer', async function() {
//     assert.equal((
//       await this.soul.balanceOf(this.seance.address)).toString(), '0');
//       await this.soul.mint(this.seance.address, 1000, { from: minter });
//       await this.seance.safeSoulTransfer(bob, 200, { from: minter });
//     assert.equal((await this.soul.balanceOf(bob)).toString(), '200');
//     assert.equal((
//       await this.soul.balanceOf(this.seance.address)).toString(), '800');
//       await this.seance.safeSoulTransfer(bob, 2000, { from: minter });
//     assert.equal((await this.soul.balanceOf(bob)).toString(), '1000');
//   });
// });
