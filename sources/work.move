module licensea::work;

use std::string::String;
use std::option::Option;
use sui::{coin::Coin, dynamic_field as df, sui::SUI};
use licensea::utils::is_prefix;

const EInvalidCap: u64 = 0;
const EInvalidFee: u64 = 1;
const ENoAccess: u64 = 2;
const MARKER: u64 = 3;
const ENotForSale: u64 = 4;
const ERevokedWork: u64 = 5;

public struct Work has key {
    id: UID,
    creator: address,
    parentId: Option<ID>, 
    metadata: Metadata,
    fee: u64,
    licenseOptions: LicenseOption,
    revoked: bool,
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
public struct View has key {
    id: UID,
    work_id: ID,
    veiwer: address, // ctx.sender가 viewer 주소랑 다르면 안됨
}

// give Cap to creator
public struct Cap has key {
    id: UID,
    work_id: ID,
}

// create Work (upload file)
fun create_work(
    metadata: Metadata,
    fee: u64,
    license_options: LicenseOption,
    ctx: &mut TxContext
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
    transfer::share_object(work);
    Cap { id: object::new(ctx), work_id }
}

fun create_work_with_parent(
    parent_work: &Work,
    metadata: Metadata,
    fee: u64,
    license_options: LicenseOption,
    ctx: &mut TxContext
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
    transfer::share_object(work);

    // Create and transfer a cap to the parent's creator
    let parent_cap = Cap { id: object::new(ctx), work_id };
    transfer::transfer(parent_cap, parent_work.creator);

    // Return a cap for the new work's creator
    Cap { id: object::new(ctx), work_id }
}

/// Entry function to create a new Work without a parent.
entry fun create_work_entry(
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
    ctx: &mut TxContext
) {
   // make Metadata struct from parameters
    let metadata = Metadata { title, description, file_type, file_size, tags, category };

    // make LicenseOption struct from parameters
    let license_option = LicenseOption {
        rule: rule,
        royaltyRatio: royaltyRatio,
    };

    // Call create_work with no parent
    let creator_cap = create_work(metadata, fee, license_option, ctx);
    transfer::transfer(creator_cap, ctx.sender());
}

/// Entry function to create a new Work with a parent.
entry fun create_work_with_parent_entry(
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
    ctx: &mut TxContext
) {
    let metadata = Metadata { title, description, file_type, file_size, tags, category };

    let license_option = LicenseOption {
        rule: rule,
        royaltyRatio: royaltyRatio,
    };

    // Call create_work with the parent
    let creator_cap = create_work_with_parent(parent_work, metadata, fee, license_option, ctx);
    transfer::transfer(creator_cap, ctx.sender());
}

entry fun pay(
    fee: Coin<SUI>,
    work: &Work,
    ctx: &mut TxContext,
) {
    assert!(!work.revoked, ERevokedWork);
    assert!(work.fee > 0, ENotForSale);
    assert!(fee.value() == work.fee, EInvalidFee);

    transfer::public_transfer(fee, work.creator);
    let view = View {
        id: object::new(ctx),
        work_id: object::id(work),
        veiwer: ctx.sender(), // todo : check ctx.sender() is viewer
    };
    transfer::transfer(view, ctx.sender());
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