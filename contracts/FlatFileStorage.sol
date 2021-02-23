
import "./StorageCore.sol";

/**
 * A simple file storage protocol using storage core.
 *
 * Ethereum account can
 *
 * - upload file
 * - list files (offchain)
 * - delete file
 *
 *
 * The rent payer for all stored files is the FlatFileStorage contract.
 * Any upload will autoamtically move tokens from uploader to FlatFileStorage for payments.
 */
 contract FlatFileStorage {

    StorageCore public core;

    // FlatFileStorage is the first application on the protocol
    uint256 public APPLICATION_ID = 0x01;

    uint128 public rentPayerAccountId;

    /**
     * Become a client for storage core protocol.
     */
    function initialise(StorageCore _core) {
        core = _core;
        rentPayerAccountId = core.openAccountForAddress(address(this));
    }

    /**
     * Upload a new file.
     *
     * All uploads are paid on the go - FlatFileStorage does not hold unused balance on storage core.
     *
     * msg.sender is set as the content owner who can later delete file.
     */
    function uploadFile(bytes32 contentHash, uint64 size, uint32 durationAsDays, uint8 contentType) {

        // Calculate indexing mask for this file
        uint256 mask = calculateMask(msg.sender, contentHash, contentType);

        (IERC20 token, uint256 cost) = core.getCurrentPricingInfo(size, durationAsDays);

        // Transfer tokens to this contract
        require(token.transferFrom(msg.sender, cost) == true, "Not enough tokens to pay for the upload");

        // Transfer tokens to the storage core for the rent
        token.approve(address(core), cost);
        core.topUpRentPayer(rentPayerAccountId, cost);

        core.storeData(contentHash, mask, size, durationAsDays, msg.sender);
    }

    function deleteFile(bytes32 contentHash) {
        // core.terminate(contentHash);
    }

    /**
     * Get the path for indexing upload files.
     *
     *
     */
    function calculateMask(address owner, bytes32 contentHash, uint8 contentType) public pure returns(uint256 mask) {

        // Get first 8 bytes of the hash
        uint256 compressedHash = uint256(hash) >> (8**24);

        uint256 mask =

            // The highest byte 31 is application id
            APPLICATION_ID << (8**31) |

            // The highest 30-10 bytes are the file owner
            uint256(owner) << (8**10) |

            // The highest bytes 9-1 are the part of the hash
            compressedHash |

            // The last byte 0 is the content type
            contentType;

        return mask;
    }

 }