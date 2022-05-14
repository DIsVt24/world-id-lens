// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { HumanCheck } from '../HumanCheck.sol';
import { Test } from 'forge-std/Test.sol';
import { LensProfile } from './mock/LensProfile.sol';
import { Semaphore } from 'worldcoin/world-id/Semaphore.sol';
import { TypeConverter } from './utils/TypeConverter.sol';

contract User {}

contract HumanCheckTest is Test {
    using TypeConverter for address;
    using TypeConverter for uint256;

    event ProfileVerified(uint256 indexed profileId);
    event ProfileUnverified(uint256 indexed profileId);

    User user;
    Semaphore semaphore;
    HumanCheck verifier;
    LensProfile profile;

    function setUp() public {
        user = new User();
        profile = new LensProfile();
        semaphore = new Semaphore();
        verifier = new HumanCheck(semaphore, 1);

        vm.label(address(user), 'User');
        vm.label(address(this), 'Sender');
        vm.label(address(profile), 'Lens Profile NFT');
        vm.label(address(verifier), 'HumanCheck');
        vm.label(address(semaphore), 'Semaphore');

        semaphore.createGroup(1, 20, 0);
    }

    function testCanVerifyProfile() public {
        uint256 profileId = profile.issue(address(this));
        assertTrue(!verifier.isVerified(profileId));

        semaphore.addMember(1, _genIdentityCommitment());
        (uint256 nullifierHash, uint256[8] memory proof) = _genProof(profileId);
        uint256 root = semaphore.getRoot(1);

        vm.expectEmit(true, false, false, true);
        emit ProfileVerified(profileId);
        verifier.verify(profileId, root, nullifierHash, proof);

        assertTrue(verifier.isVerified(profileId));
    }

    function testCanReVerifyProfile() public {
        uint256 profileId = profile.issue(address(this));
        uint256 profileId2 = profile.issue(address(this));
        assertTrue(!verifier.isVerified(profileId));
        assertTrue(!verifier.isVerified(profileId2));

        semaphore.addMember(1, _genIdentityCommitment());
        (uint256 nullifierHash, uint256[8] memory proof) = _genProof(profileId);
        uint256 root = semaphore.getRoot(1);

        verifier.verify(profileId, root, nullifierHash, proof);

        (uint256 nullifierHash2, uint256[8] memory proof2) = _genProof(profileId2);

        vm.expectEmit(true, false, false, true);
        emit ProfileUnverified(profileId);
        vm.expectEmit(true, false, false, true);
        emit ProfileVerified(profileId2);
        verifier.verify(profileId2, root, nullifierHash2, proof2);

        assertTrue(!verifier.isVerified(profileId));
        assertTrue(verifier.isVerified(profileId2));
    }

    function testCannotVerifyIfNotMember() public {
        uint256 profileId = profile.issue(address(this));
        assertTrue(!verifier.isVerified(profileId));

        semaphore.addMember(1, 1);
        (uint256 nullifierHash, uint256[8] memory proof) = _genProof(profileId);

        uint256 root = semaphore.getRoot(1);
        vm.expectRevert(abi.encodeWithSignature('InvalidProof()'));
        verifier.verify(profileId, root, nullifierHash, proof);

        assertTrue(!verifier.isVerified(profileId));
    }

    function testCannotVerifyWithInvalidSignal() public {
        uint256 profileId = profile.issue(address(this));
        assertTrue(!verifier.isVerified(profileId));

        semaphore.addMember(1, _genIdentityCommitment());
        (uint256 nullifierHash, uint256[8] memory proof) = _genProof(profileId + 1);

        uint256 root = semaphore.getRoot(1);
        vm.expectRevert(abi.encodeWithSignature('InvalidProof()'));
        verifier.verify(profileId, root, nullifierHash, proof);

        assertTrue(!verifier.isVerified(profileId));
    }

    function testCannotVerifyWithInvalidProof() public {
        uint256 profileId = profile.issue(address(this));
        assertTrue(!verifier.isVerified(profileId));

        semaphore.addMember(1, _genIdentityCommitment());

        (uint256 nullifierHash, uint256[8] memory proof) = _genProof(profileId);
        proof[0] ^= 42;

        uint256 root = semaphore.getRoot(1);
        vm.expectRevert(abi.encodeWithSignature('InvalidProof()'));
        verifier.verify(profileId, root, nullifierHash, proof);

        assertTrue(!verifier.isVerified(profileId));
    }

    function _genIdentityCommitment() internal returns (uint256) {
        string[] memory ffiArgs = new string[](2);
        ffiArgs[0] = 'node';
        ffiArgs[1] = 'src/test/scripts/generate-commitment.js';

        bytes memory returnData = vm.ffi(ffiArgs);
        return abi.decode(returnData, (uint256));
    }

    function _genProof(uint256 profileId) internal returns (uint256, uint256[8] memory proof) {
        string[] memory ffiArgs = new string[](5);
        ffiArgs[0] = 'node';
        ffiArgs[1] = '--no-warnings';
        ffiArgs[2] = 'src/test/scripts/generate-proof.js';
        ffiArgs[3] = address(verifier).toString();
        ffiArgs[4] = profileId.toString();

        bytes memory returnData = vm.ffi(ffiArgs);

        return abi.decode(returnData, (uint256, uint256[8]));
    }
}