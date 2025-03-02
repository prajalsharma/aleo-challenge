import token_registry.aleo;
import credits.aleo;

program token_vesting_linear_prajal.aleo {

    record VestingReceipt {
        beneficiary: address,
        vesting_id: field
    }

    struct VestingSchedule {
        vesting_id: field,
        asset_id: field,
        total_amount: u128,
        distributed_amount: u128,
        commencement_block: u32,
        interval_blocks: u32,
    }

    mapping schedules: field => VestingSchedule;

    async transition initialize_vesting (
        vesting_id: field,
        asset: token_registry.aleo/Token,
        quantity: u128,
        recipient: address,
        public start_block: u32,
        public duration_blocks: u32,
    ) -> (token_registry.aleo/Token, VestingReceipt, Future) { 

        let transfer_response: (token_registry.aleo/Token, Future) = token_registry.aleo/transfer_private_to_public(
            self.address,
            quantity,
            asset
        );

        let vesting_receipt: VestingReceipt = VestingReceipt {
            beneficiary: recipient,
            vesting_id: vesting_id
        };

        return (
            transfer_response.0,
            vesting_receipt,
            execute_vesting(
                transfer_response.1,
                vesting_id,
                asset.token_id,
                duration_blocks,
                quantity,
                start_block
            )
        );
    }

    async function execute_vesting(
        f0: Future,
        vesting_id: field,
        asset_id: field,
        duration_blocks: u32,
        quantity: u128,
        start_block: u32
    ){
        f0.await();

        assert(!schedules.contains(vesting_id));

        schedules.set(vesting_id, VestingSchedule {
            vesting_id: vesting_id,
            asset_id: asset_id,
            total_amount: quantity,
            distributed_amount: 0u128,
            commencement_block: start_block,
            interval_blocks: duration_blocks / 1000u128 as u32
        });
    }

    async transition withdraw (
        receipt: VestingReceipt,
        vesting_data: VestingSchedule,
        withdraw_amount: u128,
        token_validation: bool
    ) -> (
        token_registry.aleo/Token,
        VestingReceipt,
        Future
    ) {
        let new_distributed: u128 = vesting_data.distributed_amount + withdraw_amount;
        assert_eq(receipt.vesting_id, vesting_data.vesting_id);
        assert(new_distributed <= vesting_data.total_amount);

        let transfer_result: (token_registry.aleo/Token, Future) = 
            token_registry.aleo/transfer_public_to_private(
                vesting_data.asset_id,
                receipt.beneficiary,
                withdraw_amount,
                token_validation
            );

        let distribution_ratio: u128 = (new_distributed * 1000u128) / vesting_data.total_amount;

        return (
            transfer_result.0,
            receipt,
            finalize_withdrawal(
                transfer_result.1,
                vesting_data.vesting_id,
                BHP256::hash_to_field(vesting_data),
                distribution_ratio,
                new_distributed
            )
        );
    }

    async function finalize_withdrawal(
        f0: Future,
        vesting_id: field,
        vesting_hash: field,
        distributed_ratio: u128,
        new_distributed: u128
    ){
        let vesting_details: VestingSchedule = schedules.get(vesting_id);

        assert_eq(vesting_hash, BHP256::hash_to_field(vesting_details));

        let available_units: u128 = ((block.height - vesting_details.commencement_block) / vesting_details.interval_blocks) as u128;

        assert(distributed_ratio <= available_units);

        schedules.set(vesting_id, VestingSchedule {
            vesting_id: vesting_details.vesting_id,
            asset_id: vesting_details.asset_id,
            total_amount: vesting_details.total_amount,
            distributed_amount: new_distributed,
            commencement_block: vesting_details.commencement_block,
            interval_blocks: vesting_details.interval_blocks
        });

        f0.await();
    }
}
