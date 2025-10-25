// SPDX-License-Identifier: MIT
use starknet::ContractAddress;
use starknet::syscalls;
use starknet::get_caller_address;

// Define the interface for the Crowdfunding Registry contract
#[starknet::interface]
pub trait IRegistry<TContractState> {
    fn create_campaign(ref self: TContractState, title: felt252, details: felt252, goal_amount: u128);
    fn pay_campaign(ref self: TContractState, campaign_id: u64, amount: u128);
    fn get_campaign_goal(self: @TContractState, campaign_id: u64) -> u128;
    fn get_campaign_progress(self: @TContractState, campaign_id: u64) -> u128;
    fn withdraw_campaign_amount(ref self: TContractState, campaign_id: u64);
}

// Define the interface for an external ERC20 token contract
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u128) -> bool;
}

// Define the contract module
#[starknet::contract]
pub mod Registry {
    use starknet::ContractAddress;
    use starknet::storage::*; // Corrected storage import
    use starknet::get_caller_address;
    use starknet::syscalls::deploy_syscall;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    // Data structure for a single campaign
    #[derive(Drop, starknet::Store)] // Derive Store for structs used in Maps
    pub struct CampaignDetails {
        pub title: felt252,
        pub details: felt252,
        pub creator: ContractAddress,
        pub goal_amount: u128,
        pub raised_amount: u128,
        pub completed: bool,
    }

    // The main storage struct for the contract
    #[storage]
    pub struct Storage {
        campaigns: Map<u64, CampaignDetails>,
        contributions: Map<(ContractAddress, u64), u128>,
        next_campaign_id: u64,
        token_address: ContractAddress,
    }

    // Constructor to initialize the contract
    #[constructor]
    fn constructor(ref self: ContractState, initial_token_address: ContractAddress) {
        self.token_address.write(initial_token_address);
        self.next_campaign_id.write(0);
    }

    // Define contract events
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        CampaignCreated: CampaignCreatedEvent, // Renamed for clarity
        PaidToCampaign: PaidToCampaign,
        CampaignGoalReached: CampaignGoalReachedEvent, // Renamed
        CampaignProgressUpdated: CampaignProgressUpdatedEvent, // Renamed
        Withdrawn: Withdrawn,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCreatedEvent { // Renamed to avoid potential conflict
        pub creator: ContractAddress,
        pub campaign_id: u64,
        pub goal_amount: u128,
        pub title: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PaidToCampaign {
        pub campaign_id: u64,
        pub contributor: ContractAddress, // Corrected Contributor casing
        pub amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignGoalReachedEvent { // Renamed and syntax corrected
        pub campaign_id: u64, // Added campaign_id for context in event
        pub goal_amount: u128, // Corrected semicolon to comma
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignProgressUpdatedEvent { // Renamed and syntax corrected
        pub campaign_id: u64, // Added campaign_id for context in event
        pub new_total: u128, // Corrected semicolon to comma
    }

    #[derive(Drop, starknet::Event)] // Added Drop derive
    pub struct Withdrawn {
        pub campaign_id: u64,
        pub to: ContractAddress,
        pub amount: u128,
    }

    // Implementing the contract interface
    #[abi(embed_v0)]
    pub impl RegistryImpl of super::IRegistry<ContractState> {
        fn create_campaign(ref self: ContractState, title: felt252, details: felt252, goal_amount: u128) {
            let creator = get_caller_address();
            let current_id = self.next_campaign_id.read();

            let new_campaign = CampaignDetails {
                title,
                details,
                creator,
                goal_amount,
                raised_amount: 0,
                completed: false,
            };
            self.campaigns.write(current_id, new_campaign);
            self.next_campaign_id.write(current_id + 1);

            self.emit(Event::CampaignCreated(CampaignCreatedEvent {
                creator,
                campaign_id: current_id,
                goal_amount,
                title,
            }));
        }

        fn pay_campaign(ref self: ContractState, campaign_id: u64, amount: u128) {
            let contributor = get_caller_address();

            assert(amount != 0, 'AMOUNT_CANNOT_BE_ZERO');

            let mut campaign = self.campaigns.read(campaign_id);
            campaign.raised_amount += amount;

            if campaign.raised_amount >= campaign.goal_amount {
                campaign.completed = true;
                self.emit(Event::CampaignGoalReached(CampaignGoalReachedEvent { campaign_id, goal_amount: campaign.goal_amount }));
            }
            self.campaigns.write(campaign_id, campaign);

            self.contributions.write((contributor, campaign_id), amount);

            self.emit(Event::PaidToCampaign(PaidToCampaign { campaign_id, contributor, amount }));
            self.emit(Event::CampaignProgressUpdated(CampaignProgressUpdatedEvent { campaign_id, new_total:amount }));
        }

        fn get_campaign_goal(self: @ContractState, campaign_id: u64) -> u128 {
            self.campaigns.read(campaign_id).goal_amount
        }

        fn get_campaign_progress(self: @ContractState, campaign_id: u64) -> u128 {
            self.campaigns.read(campaign_id).raised_amount
        }

        fn withdraw_campaign_amount(ref self: ContractState, campaign_id: u64) {
            let withdrawer = get_caller_address();

            let mut campaign = self.campaigns.read(campaign_id);

            assert(withdrawer == campaign.creator, 'NOT_CAMPAIGN_CREATOR');

            let amount_to_withdraw = campaign.raised_amount;
            if amount_to_withdraw == 0 {
                return ();
            }

            campaign.raised_amount = 0;
            self.campaigns.write(campaign_id, campaign);

            let token_address = self.token_address.read();
            let erc20_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let success = erc20_dispatcher.transfer(withdrawer, amount_to_withdraw);
            assert(success, 'ERC20_TRANSFER_FAILED');

            self.emit(Event::Withdrawn(Withdrawn { campaign_id, to: withdrawer, amount: amount_to_withdraw }));
        }
    }
}