import { expect } from "chai";
import { ethers } from "hardhat";
import { SimpleSwap, TokenA, TokenB } from "../typechain-types";

describe("SimpleSwap", function () {
  let simpleSwap: SimpleSwap;
  let tokenA: TokenA;
  let tokenB: TokenB;
  let deployer: any;
  let user: any;

  const initialSupply = ethers.parseEther("30000");

  before(async function () {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    user = signers[1];

    const TokenAFactory = await ethers.getContractFactory("TokenA");
    tokenA = await TokenAFactory.deploy(deployer.address, { gasLimit: 3000000 });
    await tokenA.waitForDeployment();

    const TokenBFactory = await ethers.getContractFactory("TokenB");
    tokenB = await TokenBFactory.deploy(deployer.address, { gasLimit: 3000000 });
    await tokenB.waitForDeployment();
  });

  async function resetTokenBalances() {
    await tokenA.mint(deployer.address, initialSupply, { gasLimit: 3000000 });
    await tokenB.mint(deployer.address, initialSupply, { gasLimit: 3000000 });
    await tokenA.mint(user.address, ethers.parseEther("1000"), { gasLimit: 3000000 });
    await tokenB.mint(user.address, ethers.parseEther("1000"), { gasLimit: 3000000 });
  }

  describe("Deployment", function () {
    beforeEach(async function () {
      const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
      simpleSwap = await SimpleSwapFactory.deploy(deployer.address, { gasLimit: 3000000 });
      await simpleSwap.waitForDeployment();
      await resetTokenBalances();
    });

    it("Should deploy TokenA and TokenB correctly", async function () {
      expect(await tokenA.totalSupply()).to.equal(initialSupply + ethers.parseEther("1000"));
      expect(await tokenB.totalSupply()).to.equal(initialSupply + ethers.parseEther("1000"));
      expect(await tokenA.balanceOf(deployer.address)).to.equal(initialSupply);
      expect(await tokenB.balanceOf(deployer.address)).to.equal(initialSupply);
    });

    it("Should deploy SimpleSwap correctly", async function () {
      const address = await simpleSwap.getAddress();
      expect(typeof address).to.equal("string");
      expect(address.length).to.be.greaterThan(0);
    });
  });

  describe("addLiquidity", function () {
    const amountA = ethers.parseEther("100");
    const amountB = ethers.parseEther("100");

    beforeEach(async function () {
      const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
      simpleSwap = await SimpleSwapFactory.deploy(deployer.address, { gasLimit: 3000000 });
      await simpleSwap.waitForDeployment();
      await resetTokenBalances();

      await tokenA.approve(await simpleSwap.getAddress(), amountA, { gasLimit: 3000000 });
      await tokenB.approve(await simpleSwap.getAddress(), amountB, { gasLimit: 3000000 });
    });

    it("Should add initial liquidity and mint liquidity tokens", async function () {
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          amountA,
          amountB,
          amountA,
          amountB,
          deployer.address,
          deadline,
          { gasLimit: 3000000 },
        ),
      )
        .to.emit(simpleSwap, "LiquidityAction")
        .withArgs(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          amountA,
          amountB,
          ethers.parseEther("300"),
          true,
        );

      const [contractPairHash] = await simpleSwap._getPairHash(await tokenA.getAddress(), await tokenB.getAddress());
      expect(await simpleSwap.getLiquidityBalance(contractPairHash, deployer.address)).to.equal(
        ethers.parseEther("300"),
      );

      const [reserveA, reserveB] = await simpleSwap.getReserves(await tokenA.getAddress(), await tokenB.getAddress());
      expect(reserveA).to.equal(amountA);
      expect(reserveB).to.equal(amountB);
    });

    it("Should add more liquidity proportionally", async function () {
      const initialAmount = ethers.parseEther("100");
      await tokenA.approve(await simpleSwap.getAddress(), initialAmount, { gasLimit: 3000000 });
      await tokenB.approve(await simpleSwap.getAddress(), initialAmount, { gasLimit: 3000000 });
      const latestBlockInitial = await ethers.provider.getBlock("latest");
      const deadlineInitial = latestBlockInitial
        ? latestBlockInitial.timestamp + 3600
        : Math.floor(Date.now() / 1000) + 3600;
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        initialAmount,
        initialAmount,
        0n,
        0n,
        deployer.address,
        deadlineInitial,
        { gasLimit: 3000000 },
      );

      const moreAmountA = ethers.parseEther("50");
      const moreAmountB = ethers.parseEther("50");
      await tokenA.approve(await simpleSwap.getAddress(), moreAmountA, { gasLimit: 3000000 });
      await tokenB.approve(await simpleSwap.getAddress(), moreAmountB, { gasLimit: 3000000 });
      const latestBlockMore = await ethers.provider.getBlock("latest");
      const deadlineMore = latestBlockMore ? latestBlockMore.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          moreAmountA,
          moreAmountB,
          0n,
          0n,
          deployer.address,
          deadlineMore,
          { gasLimit: 3000000 },
        ),
      )
        .to.emit(simpleSwap, "LiquidityAction")
        .withArgs(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          moreAmountA,
          moreAmountB,
          ethers.parseEther("50"),
          true,
        );

      const [contractPairHash] = await simpleSwap._getPairHash(await tokenA.getAddress(), await tokenB.getAddress());
      expect(await simpleSwap.getLiquidityBalance(contractPairHash, deployer.address)).to.equal(
        ethers.parseEther("150"),
      );
    });

    it("Should revert if deadline is exceeded", async function () {
      const expiredDeadline = (await ethers.provider.getBlock("latest"))!.timestamp - 1;
      await expect(
        simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          amountA,
          amountB,
          0n,
          0n,
          deployer.address,
          expiredDeadline,
          { gasLimit: 3000000 },
        ),
      ).to.be.revertedWith("Expired deadline");
    });

    it("Should revert if insufficient amount provided", async function () {
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await expect(
        simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          amountA,
          amountB,
          amountA + 1n,
          amountB,
          deployer.address,
          deadline,
          { gasLimit: 3000000 },
        ),
      ).to.be.revertedWith("Insufficient amount provided");
    });
  });

  describe("removeLiquidity", function () {
    const initialAmount = ethers.parseEther("100");
    let contractPairHash: string;

    beforeEach(async function () {
      const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
      simpleSwap = await SimpleSwapFactory.deploy(deployer.address, { gasLimit: 3000000 });
      await simpleSwap.waitForDeployment();
      await resetTokenBalances();

      await tokenA.approve(await simpleSwap.getAddress(), initialAmount, { gasLimit: 3000000 });
      await tokenB.approve(await simpleSwap.getAddress(), initialAmount, { gasLimit: 3000000 });
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        initialAmount,
        initialAmount,
        0n,
        0n,
        deployer.address,
        deadline,
        { gasLimit: 3000000 },
      );
      [contractPairHash] = await simpleSwap._getPairHash(await tokenA.getAddress(), await tokenB.getAddress());
    });

    it("Should remove liquidity and return tokens", async function () {
      const liquidityToRemove = ethers.parseEther("50");
      const deployerInitialTokenABalance = await tokenA.balanceOf(deployer.address);
      const deployerInitialTokenBBalance = await tokenB.balanceOf(deployer.address);

      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap.removeLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          liquidityToRemove,
          0n,
          0n,
          deployer.address,
          deadline,
          { gasLimit: 3000000 },
        ),
      )
        .to.emit(simpleSwap, "LiquidityAction")
        .withArgs(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          ethers.parseEther("50"),
          ethers.parseEther("50"),
          liquidityToRemove,
          false,
        );

      expect(await simpleSwap.getLiquidityBalance(contractPairHash, deployer.address)).to.equal(
        ethers.parseEther("50"),
      );

      expect(await tokenA.balanceOf(deployer.address)).to.equal(deployerInitialTokenABalance + ethers.parseEther("50"));
      expect(await tokenB.balanceOf(deployer.address)).to.equal(deployerInitialTokenBBalance + ethers.parseEther("50"));
    });

    it("Should revert if insufficient liquidity", async function () {
      const liquidityToRemove = ethers.parseEther("150");
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap.removeLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          liquidityToRemove,
          0n,
          0n,
          deployer.address,
          deadline,
          { gasLimit: 3000000 },
        ),
      ).to.be.revertedWith("Insufficient liquidity");
    });

    it("Should revert if insufficient amount received", async function () {
      const liquidityToRemove = ethers.parseEther("50");
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap.removeLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          liquidityToRemove,
          ethers.parseEther("51"),
          ethers.parseEther("50"),
          deployer.address,
          deadline,
          { gasLimit: 3000000 },
        ),
      ).to.be.revertedWith("Insufficient amount received");
    });
  });

  describe("swapExactTokensForTokens", function () {
    const initialLiquidityA = ethers.parseEther("1000");
    const initialLiquidityB = ethers.parseEther("1000");

    beforeEach(async function () {
      const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
      simpleSwap = await SimpleSwapFactory.deploy(deployer.address, { gasLimit: 3000000 });
      await simpleSwap.waitForDeployment();
      await resetTokenBalances();

      await tokenA.approve(await simpleSwap.getAddress(), initialLiquidityA, { gasLimit: 3000000 });
      await tokenB.approve(await simpleSwap.getAddress(), initialLiquidityB, { gasLimit: 3000000 });
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        initialLiquidityA,
        initialLiquidityB,
        0n,
        0n,
        deployer.address,
        deadline,
        { gasLimit: 3000000 },
      );

      await tokenA
        .connect(user)
        .approve(await simpleSwap.getAddress(), ethers.parseEther("100"), { gasLimit: 3000000 });
      await tokenB
        .connect(user)
        .approve(await simpleSwap.getAddress(), ethers.parseEther("100"), { gasLimit: 3000000 });
    });

    it("Should swap TokenA for TokenB", async function () {
      const amountIn = ethers.parseEther("10");

      const amountInWithFee = (amountIn * ethers.toBigInt(997)) / ethers.toBigInt(1000);
      const numerator = amountInWithFee * initialLiquidityB;
      const denominator = initialLiquidityA + amountInWithFee;
      const expectedAmountOut = numerator / denominator;

      const userInitialTokenABalance = await tokenA.balanceOf(user.address);
      const userInitialTokenBBalance = await tokenB.balanceOf(user.address);
      const simpleSwapInitialTokenABalance = await tokenA.balanceOf(await simpleSwap.getAddress());
      const simpleSwapInitialTokenBBalance = await tokenB.balanceOf(await simpleSwap.getAddress());

      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            expectedAmountOut,
            [await tokenA.getAddress(), await tokenB.getAddress()],
            user.address,
            deadline,
            { gasLimit: 3000000 },
          ),
      )
        .to.emit(simpleSwap, "Swap")
        .withArgs(await tokenA.getAddress(), await tokenB.getAddress(), amountIn, expectedAmountOut);

      expect(await tokenA.balanceOf(user.address)).to.equal(userInitialTokenABalance - amountIn);
      expect(await tokenB.balanceOf(user.address)).to.equal(userInitialTokenBBalance + expectedAmountOut);
      expect(await tokenA.balanceOf(await simpleSwap.getAddress())).to.equal(simpleSwapInitialTokenABalance + amountIn);
      expect(await tokenB.balanceOf(await simpleSwap.getAddress())).to.equal(
        simpleSwapInitialTokenBBalance - expectedAmountOut,
      );
    });

    it("Should swap TokenB for TokenA", async function () {
      const amountIn = ethers.parseEther("10");

      const amountInWithFee = (amountIn * ethers.toBigInt(997)) / ethers.toBigInt(1000);
      const numerator = amountInWithFee * initialLiquidityA;
      const denominator = initialLiquidityB + amountInWithFee;
      const expectedAmountOut = numerator / denominator;

      const userInitialTokenABalance = await tokenA.balanceOf(user.address);
      const userInitialTokenBBalance = await tokenB.balanceOf(user.address);
      const simpleSwapInitialTokenABalance = await tokenA.balanceOf(await simpleSwap.getAddress());
      const simpleSwapInitialTokenBBalance = await tokenB.balanceOf(await simpleSwap.getAddress());

      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;

      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            expectedAmountOut,
            [await tokenB.getAddress(), await tokenA.getAddress()],
            user.address,
            deadline,
            { gasLimit: 3000000 },
          ),
      )
        .to.emit(simpleSwap, "Swap")
        .withArgs(await tokenB.getAddress(), await tokenA.getAddress(), amountIn, expectedAmountOut);

      expect(await tokenB.balanceOf(user.address)).to.equal(userInitialTokenBBalance - amountIn);
      expect(await tokenA.balanceOf(user.address)).to.equal(userInitialTokenABalance + expectedAmountOut);
      expect(await tokenB.balanceOf(await simpleSwap.getAddress())).to.equal(simpleSwapInitialTokenBBalance + amountIn);
      expect(await tokenA.balanceOf(await simpleSwap.getAddress())).to.equal(
        simpleSwapInitialTokenABalance - expectedAmountOut,
      );
    });

    it("Should revert if deadline is exceeded", async function () {
      const amountIn = ethers.parseEther("10");
      const expiredDeadline = (await ethers.provider.getBlock("latest"))!.timestamp - 1;
      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            0n,
            [await tokenA.getAddress(), await tokenB.getAddress()],
            user.address,
            expiredDeadline,
            { gasLimit: 3000000 },
          ),
      ).to.be.revertedWith("Expired deadline");
    });

    it("Should revert if invalid path length", async function () {
      const amountIn = ethers.parseEther("10");
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(amountIn, 0n, [await tokenA.getAddress()], user.address, deadline, {
            gasLimit: 3000000,
          }),
      ).to.be.revertedWith("Invalid path length");
    });

    it("Should revert if insufficient output amount", async function () {
      const amountIn = ethers.parseEther("10");
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await expect(
        simpleSwap
          .connect(user)
          .swapExactTokensForTokens(
            amountIn,
            ethers.parseEther("100"),
            [await tokenA.getAddress(), await tokenB.getAddress()],
            user.address,
            deadline,
            { gasLimit: 3000000 },
          ),
      ).to.be.revertedWith("Insufficient output amount");
    });
  });

  describe("Read Functions", function () {
    const initialLiquidityA = ethers.parseEther("1000");
    const initialLiquidityB = ethers.parseEther("1000");

    beforeEach(async function () {
      const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
      simpleSwap = await SimpleSwapFactory.deploy(deployer.address, { gasLimit: 3000000 });
      await simpleSwap.waitForDeployment();
      await resetTokenBalances();

      await tokenA.approve(await simpleSwap.getAddress(), initialLiquidityA);
      await tokenB.approve(await simpleSwap.getAddress(), initialLiquidityB);
      const latestBlock = await ethers.provider.getBlock("latest");
      const deadline = latestBlock ? latestBlock.timestamp + 3600 : Math.floor(Date.now() / 1000) + 3600;
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        initialLiquidityA,
        initialLiquidityB,
        0n,
        0n,
        deployer.address,
        deadline,
      );
    });

    it("Should return correct reserves", async function () {
      const [reserveA, reserveB] = await simpleSwap.getReserves(await tokenA.getAddress(), await tokenB.getAddress());
      expect(reserveA).to.equal(initialLiquidityA);
      expect(reserveB).to.equal(initialLiquidityB);
    });

    it("Should return correct price", async function () {
      const expectedPrice = (initialLiquidityB * ethers.parseEther("1")) / initialLiquidityA;
      const price = await simpleSwap.getPrice(await tokenA.getAddress(), await tokenB.getAddress());
      expect(price).to.equal(expectedPrice);
    });

    it("Should revert getPrice if reserveA is zero", async function () {
      const newTokenAFactory = await ethers.getContractFactory("TokenA");
      const newTokenA = await newTokenAFactory.deploy(deployer.address);
      await newTokenA.waitForDeployment();

      const newTokenBFactory = await ethers.getContractFactory("TokenB");
      const newTokenB = await newTokenBFactory.deploy(deployer.address);
      await newTokenB.waitForDeployment();

      await expect(simpleSwap.getPrice(await newTokenA.getAddress(), await newTokenB.getAddress())).to.be.revertedWith(
        "ReserveA is zero",
      );
    });

    it("Should calculate amount out correctly", async function () {
      const amountIn = ethers.parseEther("10");
      const reserveIn = ethers.parseEther("1000");
      const reserveOut = ethers.parseEther("1000");
      const expectedAmountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
      expect(await simpleSwap.getAmountOut(amountIn, reserveIn, reserveOut)).to.equal(expectedAmountOut);
    });

    it("Should revert getAmountOut if amountIn is zero", async function () {
      await expect(simpleSwap.getAmountOut(0n, ethers.parseEther("100"), ethers.parseEther("100"))).to.be.revertedWith(
        "AmountIn must be greater than zero",
      );
    });

    it("Should revert getAmountOut if reserveIn is zero", async function () {
      await expect(simpleSwap.getAmountOut(ethers.parseEther("10"), 0n, ethers.parseEther("100"))).to.be.revertedWith(
        "ReserveIn must be greater than zero",
      );
    });

    it("Should revert getAmountOut if reserveOut is zero", async function () {
      await expect(simpleSwap.getAmountOut(ethers.parseEther("10"), ethers.parseEther("100"), 0n)).to.be.revertedWith(
        "ReserveOut must be greater than zero",
      );
    });
  });
});
