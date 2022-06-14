// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;


contract Lottery{
    struct BetInfo{
        uint256 answerBlockNumber; // 베팅한 블록 (내 블록 다음 3번째)
        address payable bettor; // 베팅한 사람
        bytes1 challenges; // 0xab (추첨 번호)
    }

    uint256 private _tail; // BetInfo의 끝 인덱스
    uint256 private _head; // BetInfo의 처음 인덱스
    mapping (uint256 => BetInfo) private _bets; // 큐

    address payable public owner;

    bool private mode = false; // false - use answer for test, true - use real block hash
    bytes32 public answerForTest;

    uint256 constant internal BLOCK_LIMIT = 256;
    uint256 constant internal BET_BLOCK_INTERVAL = 3; // 내 블록 다음 3번째 블록의 주소값에 베팅
    uint256 constant internal BET_AMOUNT = 5 * 10 ** 15; // 0.005eth
    uint256 private _pot; // 팟머니

    enum BlockStatus {Checkable, NotRevealed, BlockLimitPassed} // 블록의 상태
    enum BettingResult {Fail, Win, Draw} // 베팅 결과 

    // index-몇번째 베팅인지, bettor-베팅한 사람, amount-베팅값(정해져있음), challenges-베팅한 글자, answerBlockNumber-베팅한 블록 (내 블록 다음 3번째)
    event BET(uint256 index, address bettor, uint256 amount, bytes1 challenges, uint256 answerBlockNumber);
    event WIN(uint256 index, address bettor, uint256 amount, bytes1 challenges, bytes1 answer, uint256 answerBlockNumber);
    event DRAW(uint256 index, address bettor, uint256 amount, bytes1 challenges, bytes1 answer, uint256 answerBlockNumber);
    event FAIL(uint256 index, address bettor, uint256 amount, bytes1 challenges, bytes1 answer, uint256 answerBlockNumber);
    event REFUND(uint256 index, address bettor, uint256 amount, bytes1 challenges, uint256 answerBlockNumber); // 환불 대상

    constructor() {
        owner = payable(msg.sender);
    }
  
    
    // 팟머니를 리턴하는 함수
    function getPot() public view returns(uint256 pot){
        return _pot;
    }

    // 해당 인덱스에 해당하는 BetInfo를 반환하는 함수
    function getBetInfo(uint256 index) public view returns(uint256 answerBlockNumber, address bettor, bytes1 challenges){
        BetInfo memory b = _bets[index];
        answerBlockNumber = b.answerBlockNumber;
        bettor = b.bettor;
        challenges = b.challenges;
    }

    

    // 새로운 Bet을 BetInfo 큐에 넣는 함수
    function pushBet(bytes1 challenges) internal returns(bool){
        BetInfo memory b;
        b.bettor = payable(msg.sender);
        b.answerBlockNumber = block.number + BET_BLOCK_INTERVAL;
        b.challenges = challenges;

        _bets[_tail] = b;
        _tail++;

        return true;
    }

    // 해당 인덱스에 해당하는 Bet을 삭제하는 함수
    function popBet(uint256 index) internal returns(bool){
        delete _bets[index];
        return true; 
    }

    /**
     * @dev 베팅(bet()) & 정답 체크(distribute()) 한번에 실행하는 함수
     * @param challenges - 베팅용 1byte 문자열
     * @return 함수가 잘 수행되었는지 확인하는 bool 값
     */
    function betAndDistribute(bytes1 challenges) public payable returns(bool){
        bet(challenges);
        distribute();
        return true;
    }


    /**
     * @dev 베팅을 한다. 유저는 0.005 ETH를 보내야 하고, 베팅용 1byte 문자열을 보낸다.
     * 큐에 저장된 베팅 정보는 이후 distribute 함수에서 해결된다.
     * @param challenges - 베팅용 1byte 문자열
     * @return 함수가 잘 수행되었는지 확인하는 bool 값
     */
    function bet(bytes1 challenges) public payable returns (bool){
        // 돈이 제대로 들어왔는지 확인
        require(msg.value >= BET_AMOUNT, "Not enough ETH");
        // 큐에 Bet 정보 넣기
        require(pushBet(challenges), "Fail to add a new Bet Info");
        // event log
        emit BET(_tail - 1, msg.sender, msg.value, challenges, block.number + BET_BLOCK_INTERVAL);
        return true;
    }

    /**
     * @dev 베팅 결과값을 확인하고 팟머니를 분배한다.
     * 정답 실패 -> 팟머니 축적, 정답 맞춤 -> 팟머니 획득, 한글자 맞춤 or 정답 확인 불가 -> 베팅 금액만 획득
     */
    function distribute() public{
        uint256 cur;
        uint256 transferAmount; // 당첨자에게 전송되는 금액 (수수료 제외)
        BetInfo memory b;
        BlockStatus currentBlockStatus;
        BettingResult currentBettingResult;
        
        for(cur = _head; cur < _tail; cur++){
            b = _bets[cur];
            currentBlockStatus = getBlockStatus(b.answerBlockNumber);
            
            // Block이 유효할 때 
            if(currentBlockStatus == BlockStatus.Checkable){
                bytes32 answerBlockHash = getAnswerBlockHash(b.answerBlockNumber);
                currentBettingResult = isMatch(b.challenges, answerBlockHash);
                // 두글자 모두 맞췄을 때 -> 팟머니 수령
                if(currentBettingResult == BettingResult.Win){
                    transferAmount = transferAfterPayingFee(b.bettor, _pot + BET_AMOUNT);
                    _pot = 0;
                    emit WIN(cur, b.bettor, transferAmount, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }
                // 한글자만 맞췄을 때 -> 베팅금을 돌려줌
                if(currentBettingResult == BettingResult.Draw){
                    transferAmount = transferAfterPayingFee(b.bettor, BET_AMOUNT);
                    emit DRAW(cur, b.bettor, transferAmount, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }
                // 실패했을 때 -> 베팅금이 팟머니로 ㄱㄱ
                if(currentBettingResult == BettingResult.Fail){
                    _pot += BET_AMOUNT;
                    emit FAIL(cur, b.bettor, 0, b.challenges, answerBlockHash[0], b.answerBlockNumber);
                }
            }

            // Block이 아직 마이닝이 되지 않은 상태 
            if(currentBlockStatus == BlockStatus.NotRevealed){
                break;
            }

            // Block의 제한이 지났을 때 
            if(currentBlockStatus == BlockStatus.BlockLimitPassed){
                // 환불
                transferAmount = transferAfterPayingFee(b.bettor, BET_AMOUNT);
                emit REFUND(cur, b.bettor, 0, b.challenges, b.answerBlockNumber);
            }
            popBet(cur);
        }
        _head = cur;
    }

    function getBlockStatus(uint256 answerBlockNumber) internal view returns (BlockStatus){
        if(block.number > answerBlockNumber && block.number - BLOCK_LIMIT < answerBlockNumber){
            return BlockStatus.Checkable;
        }
        if(block.number <= answerBlockNumber){
            return BlockStatus.NotRevealed;
        }
        if(block.number >= answerBlockNumber + BLOCK_LIMIT){
            return BlockStatus.BlockLimitPassed;
        }
        return BlockStatus.BlockLimitPassed;
    }

    /**
     * @dev 베팅 문자열이 정답과 일치하는지 확인하는 함수
     * @param challenges - 베팅 글자
     * @param answer - BlockHash
     * @return 정답 결과
     */
    function isMatch(bytes1 challenges, bytes32 answer) public pure returns(BettingResult){
        // challenges 0xab
        // answer axab......ff 32bytes

        bytes1 c1 = challenges;
        bytes1 c2 = challenges;

        bytes1 a1 = answer[0];
        bytes1 a2 = answer[0];

        // Get first number
        c1 = c1 >> 4; // 0xab -> 0x0a
        c1 = c1 << 4; // 0x0a -> 0xa0

        a1 = a1 >> 4;
        a1 = a1 << 4;

        // Get second number
        c2 = c2 << 4; // 0xab -> 0xb0
        c2 = c2 >> 4; // 0xb0 -> 0x0b

        a2 = a2 << 4;
        a2 = a2 >> 4;

        if(a1 == c1 && a2 == c2){
            return BettingResult.Win;
        }
        if(a1 == c1 || a2 == c2){
            return BettingResult.Draw;
        }
        return BettingResult.Fail;
    }

    function setAnswerForTest(bytes32 answer) public returns(bool result){
        require(msg.sender == owner, "Only owner can set answer for test mode");
        answerForTest = answer;
        return true;
    }
    function getAnswerBlockHash(uint256 answerBlockNumber) internal view returns(bytes32 answer){
        return mode ? blockhash(answerBlockNumber) : answerForTest;
    }

    function transferAfterPayingFee(address payable addr, uint256 amount) internal returns(uint256){
        // uint256 fee = amount / 100;
        uint256 fee = 0;
        uint256 amountWithoutFee = amount - fee;

        // transfer to addr
        addr.transfer(amountWithoutFee);

        // transfer to owner
        owner.transfer(fee);

        return amountWithoutFee;
    }
}