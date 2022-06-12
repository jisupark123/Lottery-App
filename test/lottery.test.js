const Lottery = artifacts.require('Lottery');
const assertRevert = require('./assertRevert');
const expectEvent = require('./expectEvent');

contract('Lottery', function ([deployer, user1, user2]) {
  let lottery;
  const betAmount = 5 * 10 ** 15;
  const betBlockInterval = 3;
  beforeEach(async () => {
    lottery = await Lottery.new();
  });

  it('getPot should return current pot', async () => {
    const pot = await lottery.getPot();
    assert.equal(pot, 0);
  });

  describe('Bet', function () {
    it('should fail when the bet money is not 0.005 ETH', async () => {
      // Fail transaction
      await assertRevert(
        lottery.bet('0xab', { from: user1, value: betAmount })
      );
    });
    it('should put the bet to the bet queue with 1 bet', async () => {
      // bet
      const receipt = await lottery.bet('0xab', {
        from: user1,
        value: betAmount,
      });
      // console.log(receipt);

      const pot = await lottery.getPot();
      assert.equal(pot, 0);
      // check contract balance == 0.005ETH
      const contractBalance = await web3.eth.getBalance(lottery.address);
      assert.equal(contractBalance, betAmount);
      // check bet info
      const currentBlockNumber = await web3.eth.getBlockNumber();
      const bet = await lottery.getBetInfo(0);
      assert.equal(
        bet.answerBlockNumber,
        currentBlockNumber + betBlockInterval
      );
      assert.equal(bet.bettor, user1);
      assert.equal(bet.challenges, '0xab');

      // check log
      await expectEvent.inLogs(receipt.logs, 'BET');
    });
  });

  describe('isMatch', function () {
    const blockHash =
      '0xaba75b03f0cf2a437b67ba8cbb057192c86396be08a8d101b44d7a57d1dfec14';
    it('should be BettingResult.Fail when two chars not match', async () => {
      const matchingResult = await lottery.isMatch('0xcd', blockHash);
      assert.equal(matchingResult, 0);
    });

    it('should be BettingResult.Win when two chars match', async () => {
      const matchingResult = await lottery.isMatch('0xab', blockHash);
      assert.equal(matchingResult, 1);
    });

    it('should be BettingResult.Draw when two chars match 1', async () => {
      let matchingResult = await lottery.isMatch('0xac', blockHash);
      assert.equal(matchingResult, 2);
      matchingResult = await lottery.isMatch('0xeb', blockHash);
      assert.equal(matchingResult, 2);
    });
  });
  describe('Distribute', function () {
    describe('When the answer is checkable', function () {
      it.only('should give user the pot when the answer matches', async () => {
        // 두글자 다 맞았을 때
        await lottery.setAnswerForTest(
          '0xaba75b03f0cf2a437b67ba8cbb057192c86396be08a8d101b44d7a57d1dfec14',
          { from: deployer }
        );
      });
      it('should give user the amount when a single character matches', async () => {
        // 한글자만 맞았을 때
      });
      it('should get the eth of user when the answer does not match at all', async () => {
        // 다 틀렸을 때
      });
    });
    describe('When the answer is not revealed(Not Mined)', function () {});
    describe('When the answer is not revealed(Block limit is passed)', function () {});
  });
});