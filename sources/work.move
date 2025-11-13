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

public struct Work has key {
    id: UID,
    creator: address,
    parentId: vector<ID>, 
    metadata: Metadata,
    fee: Option<u64>, // if None, it's free
    licenseOptions: LicenseOption, // 
}

public struct Metadata has copy, drop, store {
    title: String,
    description: String,
    file_type: String,
    file_size: u64,
    tags: vector<String>,
}

// license option
public struct LicenseOption has copy, drop, store {
    name: String,
    terms_url: String,
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
public fun create_work(
    parentId: vector<ID>,
    metadata: Metadata,
    fee: Option<u64>,
    license_options: LicenseOption,
    ctx: &mut TxContext
): Cap {
    let work = Work {
        id: object::new(ctx),
        creator: ctx.sender(),
        parentId: parentId, // ** parentId 어떻게 받을지
        metadata: metadata,
        fee: fee,
        licenseOptions: license_options,
    };

    let cap = Cap {
        id: object::new(ctx),
        work_id: object::id(&work),
    };
    transfer::share_object(work);
    cap
}

entry fun create_work_entry(
    // metadata field
    title: String,
    description: String,
    file_type: String,
    file_size: u64,
    tags: vector<String>,
    // licenseOptions field
    license_name: String,
    license_url: String,
    // other fields
    parentId: vector<ID>,
    fee: Option<u64>,
    ctx: &mut TxContext
) {
   // make Metadata struct from parameters
    let metadata = Metadata { title, description, file_type, file_size, tags };

    // make LicenseOption struct from parameters
    let license_options = LicenseOption {
        name: license_name,
        terms_url: license_url,
    };

    let cap = create_work(parentId, metadata, fee, license_options, ctx);
    transfer::transfer(cap, ctx.sender());
}

public fun pay(
    fee: Coin<SUI>,
    work: &Work,
    ctx: &mut TxContext,
): View {
    let work_fee = option::destroy_some(work.fee);
    assert!(fee.value() == work_fee, EInvalidFee);

    transfer::public_transfer(fee, work.creator);
    View {
        id: object::new(ctx),
        work_id: object::id(work),
        veiwer: ctx.sender(), // todo : check ctx.sender() is viewer
    }
}


public fun transfer(view: View, to: address) {
    transfer::transfer(view, to);
}

// Access control
/// key format: [pkg id]::[work id][random nonce]

/// All allowlisted addresses can access all IDs with the prefix of the allowlist
fun approve_internal(id: vector<u8>, view: &View, work: &Work): bool {
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
public fun publish(work: &mut Work, cap: &Cap, blob_id: String) {
    assert!(cap.work_id == object::id(work), EInvalidCap);
    df::add(&mut work.id, blob_id, MARKER);
}