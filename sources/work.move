module licensea::work;

use licensea::utils::is_prefix;
use std::option::Option;
use std::string::String;
use sui::coin::{Self, Coin, value};
use sui::dynamic_field as df;
use sui::sui::SUI;
use sui::table::{Self, Table};

const EInvalidCap: u64 = 0;
const EInvalidFee: u64 = 1;
const ENoAccess: u64 = 2;
const MARKER: u64 = 3;
const ENotForSale: u64 = 4;
const ERevokedWork: u64 = 5;

public struct WorkRegistry has key {
    id: UID,
    works: Table<ID, WorkRef>,
}

public struct Work has key {
    id: UID,
    creator: address,
    parentId: Option<ID>,
    metadata: Metadata,
    fee: u64,
    licenseOptions: LicenseOption,
    revoked: bool,
}

public struct WorkRef has store {
    creator: address,
    parentId: Option<ID>,
    royaltyRatio: u64, // 100 = 1%
}

public struct Metadata has copy, drop, store {
    title: String,
    description: String,
    file_type: String,
    file_size: u64,
    tags: vector<String>,
    category: String,
}

// license option
public struct LicenseOption has copy, drop, store {
    rule: String,
    royaltyRatio: u64,
}

// give View to user who paid
public struct View has key, store {
    id: UID,
    work_id: ID,
    viewer: address, // ctx.sender가 viewer 주소랑 다르면 안됨
}

// give Cap to creator
public struct Cap has key {
    id: UID,
    work_id: ID,
}

// initialize registry
fun init(ctx: &mut TxContext) {
    let registry = WorkRegistry {
        id: object::new(ctx),
        works: table::new(ctx),
    };
    transfer::share_object(registry);
}

// create Work (upload file)
fun create_work(
    registry: &mut WorkRegistry,
    metadata: Metadata,
    fee: u64,
    license_options: LicenseOption,
    ctx: &mut TxContext,
): Cap {
    let work = Work {
        id: object::new(ctx),
        creator: ctx.sender(),
        parentId: option::none(),
        metadata: metadata,
        fee: fee,
        licenseOptions: license_options,
        revoked: false,
    };

    let work_id = object::id(&work);
    let work_ref = WorkRef {
        creator: ctx.sender(),
        parentId: option::none(),
        royaltyRatio: license_options.royaltyRatio,
    };

    transfer::share_object(work);
    table::add(&mut registry.works, work_id, work_ref);

    Cap { id: object::new(ctx), work_id }
}

fun create_work_with_parent(
    registry: &mut WorkRegistry,
    parent_work: &Work,
    metadata: Metadata,
    fee: u64,
    license_options: LicenseOption,
    ctx: &mut TxContext,
): Cap {
    let work = Work {
        id: object::new(ctx),
        creator: ctx.sender(),
        parentId: option::some(object::id(parent_work)),
        metadata: metadata,
        fee: fee,
        licenseOptions: license_options,
        revoked: false,
    };

    let work_id = object::id(&work);
    let work_ref = WorkRef {
        creator: ctx.sender(),
        parentId: option::some(object::id(parent_work)),
        royaltyRatio: license_options.royaltyRatio,
    };
    transfer::share_object(work);
    table::add(&mut registry.works, work_id, work_ref);

    // Create and transfer a cap to the parent's creator
    let parent_cap = Cap { id: object::new(ctx), work_id };
    transfer::transfer(parent_cap, parent_work.creator);

    // Return a cap for the new work's creator
    Cap { id: object::new(ctx), work_id }
}

/// Entry function to create a new Work without a parent.
entry fun create_work_entry(
    registry: &mut WorkRegistry,
    // metadata field
    title: String,
    description: String,
    file_type: String,
    file_size: u64,
    tags: vector<String>,
    category: String,
    // licenseOptions field
    rule: String,
    royaltyRatio: u64,
    // other fields
    fee: u64,
    ctx: &mut TxContext,
) {
    // make Metadata struct from parameters
    let metadata = Metadata { title, description, file_type, file_size, tags, category };

    // make LicenseOption struct from parameters
    let license_option = LicenseOption {
        rule: rule,
        royaltyRatio: royaltyRatio,
    };

    // Call create_work with no parent
    let creator_cap = create_work(registry, metadata, fee, license_option, ctx);
    transfer::transfer(creator_cap, ctx.sender());
}

/// Entry function to create a new Work with a parent.
entry fun create_work_with_parent_entry(
    registry: &mut WorkRegistry,
    parent_work: &Work,
    // metadata field
    title: String,
    description: String,
    file_type: String,
    file_size: u64,
    tags: vector<String>,
    category: String,
    // licenseOptions field
    rule: String,
    royaltyRatio: u64,
    // other fields
    fee: u64,
    ctx: &mut TxContext,
) {
    let metadata = Metadata { title, description, file_type, file_size, tags, category };

    let license_option = LicenseOption {
        rule: rule,
        royaltyRatio: royaltyRatio,
    };

    // Call create_work with the parent
    let creator_cap = create_work_with_parent(
        registry,
        parent_work,
        metadata,
        fee,
        license_option,
        ctx,
    );
    transfer::transfer(creator_cap, ctx.sender());
}

entry fun pay(registry: &WorkRegistry, mut fee: Coin<SUI>, work: &Work, ctx: &mut TxContext) {
    assert!(!work.revoked, ERevokedWork);
    assert!(work.fee > 0, ENotForSale);
    assert!(fee.value() == work.fee, EInvalidFee);

    let mut remaining = value(&fee);
    let mut depth = 0;
    let max_depth = 3u64;
    let mut current_parent = &work.parentId;

    if (option::is_none(current_parent)) {
        transfer::public_transfer(fee, work.creator);
    } else {
        // 1. sales revenue to work's creator
        let parent_id = *option::borrow(current_parent);
        let parent_ref = table::borrow(&registry.works, parent_id);
        let royalty = (remaining * parent_ref.royaltyRatio) / 10000;
        let amount = remaining - royalty;
        let amount_coin = coin::split(&mut fee, amount, ctx);
        transfer::public_transfer(amount_coin, work.creator);

        remaining = remaining - amount;

        // 2. royalty revenue to 3 depths parents
        while (depth < max_depth) {
            if (option::is_none(current_parent)) { break };
            if (!table::contains(&registry.works, *option::borrow(current_parent))) { break; };

            let parent_id = *option::borrow(current_parent);
            let parent_ref = table::borrow(&registry.works, parent_id);

            let is_last = (depth == max_depth - 1) || option::is_none(&parent_ref.parentId);

            if (is_last) {
                let amount_coin = coin::split(&mut fee, remaining, ctx);
                transfer::public_transfer(amount_coin, parent_ref.creator);
                remaining = 0;
                break
            } else {
                let next_parent_id = *option::borrow(&parent_ref.parentId);
                let next_parent_ref = table::borrow(&registry.works, next_parent_id);
                let royalty = (remaining * next_parent_ref.royaltyRatio) / 10000;
                let amount = remaining - royalty;
                let amount_coin = coin::split(&mut fee, amount, ctx);
                transfer::public_transfer(amount_coin, parent_ref.creator);
                remaining = remaining - amount;
            };

            current_parent = &parent_ref.parentId;
            depth = depth + 1;
        };

        transfer::public_transfer(fee, work.creator);
    };

    let view = View {
        id: object::new(ctx),
        work_id: object::id(work),
        viewer: ctx.sender(), // todo : check ctx.sender() is viewer
    };
    transfer::public_transfer(view, ctx.sender())
}

// Access control
/// key format: [pkg id]::[work id][random nonce]

/// check if the given seal id is the right id for the work
fun approve_internal(id: vector<u8>, view: &View, work: &Work): bool {
    if (work.revoked) return false;
    if (object::id(work) != view.work_id) {
        return false
    };

    // Check if the id has the right prefix
    is_prefix(work.id.to_bytes(), id)
}

entry fun seal_approve(id: vector<u8>, view: &View, work: &Work) {
    assert!(approve_internal(id, view, work), ENoAccess);
}

/// Encapsulate a blob into a Sui object and attach it to the Subscription
entry fun publish(work: &mut Work, cap: &Cap, blob_id: String) {
    assert!(cap.work_id == object::id(work), EInvalidCap);
    df::add(&mut work.id, blob_id, MARKER);
}

/// Set Work revocation - only the Cap holder (creator) can do this
entry fun set_revoke_work(work: &mut Work, cap: &Cap) {
    assert!(cap.work_id == object::id(work), EInvalidCap);
    work.revoked = !work.revoked;
}
