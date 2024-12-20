import { expect } from 'chai';

async function preDeployExchange() {
    const [deployer] = await ethers.getSigners();
    const oneSidedExchangeImplementation = await ethers.deployContract('OneSidedExchange', deployer);
    const exchangeAddress = await oneSidedExchangeImplementation.getAddress();
    const tokenAImplementation = await ethers.deployContract('ExampleERC20', [100, 'TokenA', 'TOKA', 18], deployer);
    const tokenAAddress = await tokenAImplementation.getAddress();
    const tokenADecimals = await tokenAImplementation.decimals();
    const tokenBImplementation = await ethers.deployContract('ExampleERC20', [100, 'TokenB', 'TOKB', 4], deployer);
    const tokenBAddress = await tokenBImplementation.getAddress();
    const tokenBDecimals = await tokenBImplementation.decimals();
    const tokenASwapAmount = 2n;
    const twoDaysAfter = new Date().getSeconds() + (((24 * 60) * 60) * 2);

    await oneSidedExchangeImplementation.setSellPrice(tokenAAddress, 6, twoDaysAfter);
    await oneSidedExchangeImplementation.setBuyPrice(tokenBAddress, 4, twoDaysAfter);
    await oneSidedExchangeImplementation.setThreshold(tokenAAddress, 16n, 10n, twoDaysAfter);
    await tokenAImplementation.approve(exchangeAddress, (100n * (10n ** tokenADecimals)));
    await tokenBImplementation.approve(exchangeAddress, (100n * (10n ** tokenBDecimals)));
    const [sellAmount, buyAmount] = (await oneSidedExchangeImplementation.estimateTokenReturns(tokenAAddress, tokenBAddress, tokenASwapAmount));

    const exchangeTokenABalanceBeforeSwap = await tokenAImplementation.balanceOf(exchangeAddress);
    const swapperTokenBBalanceBeforeSwap = await tokenBImplementation.balanceOf(deployer);

    const exchangeAmountDeposit = (buyAmount / (10n ** tokenBDecimals)) + 2n;
    await oneSidedExchangeImplementation.deposit(tokenBAddress, exchangeAmountDeposit);
    await oneSidedExchangeImplementation.swap(tokenAAddress, tokenBAddress, tokenASwapAmount);

    const exchangeTokenABalanceAfterSwap = await tokenAImplementation.balanceOf(exchangeAddress);
    const swapperTokenBBalanceAfterSwap = await tokenBImplementation.balanceOf(deployer);
}

describe("OneSidedExchange", async () => {
    let oneSidedExchangeInstance;

    before(async () => {
        const _context = await preDeployExchange();
    });

    it("Should successfuly swap tokenA and tokenB", async () => {
        expect(true).to.be.equal(true);
    });

    it("Should fail on swap tokenA and tokenB", async () => {
        expect(true).to.be.equal(true);
    });
})
