import { expect } from "chai";

async function preDeployExchange() {
    const [deployer] = await ethers.getSigners();
    const oneSidedExchangeImplementation = await ethers.deployContract("OneSidedExchange", deployer);
    const tokenAImplementation = await ethers.deployContract("ExampleERC20", [100, "TokenA", "TOKA"], deployer);
    const tokenBImplementation = await ethers.deployContract("ExampleERC20", [100, "TokenB", "TOKB"], deployer);

    return [oneSidedExchangeImplementation, tokenAImplementation, tokenBImplementation];
}

describe("OneSidedExchange", async () => {
    let oneSidedExchangeInstance;
    let tokenAInstance;
    let tokenBInstance;
    let owner;

    before(async () => {
        const [deployer] = await ethers.getSigners();
        [oneSidedExchangeInstance, tokenAInstance, tokenBInstance] = await preDeployExchange();
        owner = deployer;
    })

    it("Should successfuly swap tokenA and tokenB", async () => {
        const exchangeAddress = await oneSidedExchangeInstance.getAddress();
        const tokenAAddress = await tokenAInstance.getAddress();
        const tokenADecimals = await tokenAInstance.decimals();
        const tokenBAddress = await tokenBInstance.getAddress();
        const tokenBDecimals = await tokenBInstance.decimals();
        // Set days threshold to 2.
        const twoDaysAfter = new Date().getSeconds() + (((24 * 60) * 60) * 2);
        // Set token swap amount to 2.
        const tokenASwapAmount = 2n;

        // Set sell price for token A to 6.
        await oneSidedExchangeInstance.setSellPrice(tokenAAddress, 6, twoDaysAfter);
        // Set buy price for token B to 4.
        await oneSidedExchangeInstance.setBuyPrice(tokenBAddress, 4, twoDaysAfter);
        // Approve exchange to use n amount of tokens.
        await tokenAInstance.approve(exchangeAddress, (100n * (10n ** tokenADecimals)));
        await tokenBInstance.approve(exchangeAddress, (100n * (10n ** tokenBDecimals)));

        const [_, buyAmount] = (await oneSidedExchangeInstance.estimateTokenReturns(tokenAAddress, tokenBAddress, tokenASwapAmount));
        const exchangeTokenABalanceBeforeSwap = await tokenAInstance.balanceOf(exchangeAddress);
        const swapperTokenBBalanceBeforeSwap = await tokenBInstance.balanceOf(owner);

        await oneSidedExchangeInstance.deposit(tokenBAddress, (buyAmount / (10n ** tokenBDecimals)) + 2n);
        await oneSidedExchangeInstance.swap(tokenAAddress, tokenBAddress, tokenASwapAmount);

        const exchangeTokenABalanceAfterSwap = await tokenAInstance.balanceOf(exchangeAddress);
        const swapperTokenBBalanceAfterSwap = await tokenBInstance.balanceOf(owner);
        const exchangeABalanceBefore = exchangeTokenABalanceBeforeSwap / (10n ** tokenADecimals);
        const exchangeABalanceAfter = exchangeTokenABalanceAfterSwap / (10n ** tokenADecimals);
        const swapperBBalanceBefore = swapperTokenBBalanceBeforeSwap / (10n ** tokenBDecimals);
        const swapperBBalanceAfter = swapperTokenBBalanceAfterSwap / (10n ** tokenBDecimals);

        expect(exchangeABalanceBefore).to.be.equal(0n);
        expect(exchangeABalanceAfter).to.be.equal(12n);
        expect(swapperBBalanceBefore).to.be.equal(100n);
        expect(swapperBBalanceAfter).to.be.equal(98n);

        await oneSidedExchangeInstance.withdraw(tokenAAddress, 2n);
    });

    it("Should fail on swap tokenA and tokenB", async () => {
        const exchangeAddress = await oneSidedExchangeInstance.getAddress();
        const tokenAAddress = await tokenAInstance.getAddress();
        const tokenADecimals = await tokenAInstance.decimals();
        const tokenBAddress = await tokenBInstance.getAddress();
        const tokenBDecimals = await tokenBInstance.decimals();

        // Set days threshold to 2 days.
        const twoDaysAfterInSeconds = new Date().getSeconds() + (((24 * 60) * 60) * 2);
        // Set token swap amount to 2.
        const tokenASwapAmount = 2n;
        // Set token A max sell amount to 16 and max buy amount 10.
        const tokenASellAmount = 16n;
        const tokenABuyAmount = 10n;

        // Set sell price for token A to 6.
        await oneSidedExchangeInstance.setSellPrice(tokenAAddress, 6, twoDaysAfterInSeconds);
        // Set buy price for token B to 4.
        await oneSidedExchangeInstance.setBuyPrice(tokenBAddress, 4, twoDaysAfterInSeconds);
        await oneSidedExchangeInstance.setThreshold(tokenAAddress, tokenASellAmount, tokenABuyAmount, twoDaysAfterInSeconds);
        await tokenAInstance.approve(exchangeAddress, (100n * (10n ** tokenADecimals)));
        await tokenBInstance.approve(exchangeAddress, (100n * (10n ** tokenBDecimals)));

        const exchangeTokenABalanceBeforeSwap = await tokenAInstance.balanceOf(exchangeAddress);
        const swapperTokenBBalanceBeforeSwap = await tokenBInstance.balanceOf(owner);

        try {
            await oneSidedExchangeInstance.swap(tokenAAddress, tokenBAddress, tokenASwapAmount);

            const exchangeTokenABalanceAfterSwap = await tokenAInstance.balanceOf(exchangeAddress);
            const swapperTokenBBalanceAfterSwap = await tokenBInstance.balanceOf(owner);
            const exchangeABalanceBefore = exchangeTokenABalanceBeforeSwap / (10n ** tokenADecimals);
            const exchangeABalanceAfter = exchangeTokenABalanceAfterSwap / (10n ** tokenADecimals);
            const swapperBBalanceBefore = swapperTokenBBalanceBeforeSwap / (10n ** tokenBDecimals);
            const swapperBBalanceAfter = swapperTokenBBalanceAfterSwap / (10n ** tokenBDecimals);

            expect(exchangeABalanceBefore).to.be.equal(0n);
            expect(exchangeABalanceAfter).to.be.equal(12n);
            expect(swapperBBalanceBefore).to.be.equal(100n);
            expect(swapperBBalanceAfter).to.be.equal(98n);
        } catch (err) {
            const parsedMessage = err.message?.split("InvalidAmount")[1];

            expect(parsedMessage).to.be.includes("Max sell amount of tokens exceeded");
        }
    });

    it("Should fail on zero address provided", async () => {
        try {
            const tokenASellAmount = 16n;
            const tokenABuyAmount = 10n;
            // Set days threshold to 2 days.
            const twoDaysAfterInSeconds = new Date().getSeconds() + (((24 * 60) * 60) * 2);

            await oneSidedExchangeInstance.setThreshold(
                "0x0000000000000000000000000000000000000000",
                tokenASellAmount,
                tokenABuyAmount,
                twoDaysAfterInSeconds,
            );
        } catch (err) {
            const parsedMessage = err.message?.split("InvalidAddress")[1];

            expect(parsedMessage).to.be.includes("No zero address is allowed");
        }
    });
})
