use std::sync::Arc;
use yrs::block::BlockRange;
use yrs::updates::{decoder::Decode, encoder::Encode};
use yrs::{ClientID, IdSet, ID};

#[derive(Debug, thiserror::Error)]
pub enum YrsIdError {
    #[error("Client IDs must fit in 53 bits")]
    InvalidClientId,
    #[error("The range exceeds the 32-bit clock space")]
    InvalidRange,
    #[error("Invalid encoded ID data")]
    DecodingError,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct YrsIdRange {
    pub client_id: u64,
    pub clock: u32,
    pub length: u32,
}

pub(crate) fn client_id(value: u64) -> Result<ClientID, YrsIdError> {
    if value >= 1 << 53 {
        return Err(YrsIdError::InvalidClientId);
    }
    Ok(ClientID::new(value))
}

impl YrsIdRange {
    pub(crate) fn block_range(&self) -> Result<BlockRange, YrsIdError> {
        let client = client_id(self.client_id)?;
        self.clock.checked_add(self.length).ok_or(YrsIdError::InvalidRange)?;
        Ok(BlockRange { client, clock: self.clock, len: self.length })
    }
}

/// An immutable owned snapshot; no document or transaction lifetime is retained.
pub(crate) struct YrsIdSet(pub(crate) IdSet);

impl YrsIdSet {
    pub(crate) fn new() -> Self {
        Self(IdSet::new())
    }

    pub(crate) fn from_ranges(ranges: Vec<YrsIdRange>) -> Result<Self, YrsIdError> {
        let mut set = IdSet::new();
        for range in ranges {
            let range = range.block_range()?;
            if range.len != 0 {
                set.insert(ID::new(range.client, range.clock), range.len);
            }
        }
        Ok(Self(set))
    }

    pub(crate) fn decode_v1(data: Vec<u8>) -> Result<Self, YrsIdError> {
        IdSet::decode_v1(&data).map(Self).map_err(|_| YrsIdError::DecodingError)
    }

    pub(crate) fn decode_v2(data: Vec<u8>) -> Result<Self, YrsIdError> {
        IdSet::decode_v2(&data).map(Self).map_err(|_| YrsIdError::DecodingError)
    }

    pub(crate) fn encode_v1(&self) -> Vec<u8> { self.0.encode_v1() }
    pub(crate) fn encode_v2(&self) -> Vec<u8> { self.0.encode_v2() }
    pub(crate) fn is_empty(&self) -> bool { self.0.is_empty() }
    pub(crate) fn client_count(&self) -> u64 { self.0.len() as u64 }
    pub(crate) fn equals(&self, other: &Self) -> bool { self.0 == other.0 }

    pub(crate) fn ranges(&self) -> Vec<YrsIdRange> {
        self.0.iter().flat_map(|(client, ranges)| {
            ranges.iter().map(move |range| YrsIdRange {
                client_id: client.get(), clock: range.start, length: range.end - range.start,
            })
        }).collect()
    }

    pub(crate) fn contains(&self, client: u64, clock: u32) -> Result<bool, YrsIdError> {
        Ok(self.0.contains(&ID::new(client_id(client)?, clock)))
    }

    pub(crate) fn with_range(&self, range: YrsIdRange) -> Result<Arc<Self>, YrsIdError> {
        let range = range.block_range()?;
        let mut set = self.0.clone();
        if range.len != 0 { set.insert(ID::new(range.client, range.clock), range.len); }
        Ok(Arc::new(Self(set)))
    }

    pub(crate) fn without_range(&self, range: YrsIdRange) -> Result<Arc<Self>, YrsIdError> {
        let range = range.block_range()?;
        let mut set = self.0.clone();
        set.remove_range(&range);
        Ok(Arc::new(Self(set)))
    }

    pub(crate) fn union(&self, other: &Self) -> Arc<Self> {
        Arc::new(Self(self.0.merge(&other.0)))
    }

    pub(crate) fn difference(&self, other: &Self) -> Arc<Self> {
        Arc::new(Self(self.0.diff(&other.0)))
    }

    pub(crate) fn intersection(&self, other: &Self) -> Arc<Self> {
        Arc::new(Self(self.0.intersect(&other.0)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use yrs::encoding::write::Write;
    use yrs::updates::encoder::{Encoder, EncoderV1, EncoderV2};

    #[test]
    fn validates_ranges_and_preserves_value_semantics() {
        let range = YrsIdRange { client_id: (1 << 53) - 1, clock: 2, length: 6 };
        let set = YrsIdSet::from_ranges(vec![range.clone()]).unwrap();
        let removed = set.without_range(YrsIdRange { clock: 4, length: 2, ..range.clone() }).unwrap();
        assert_eq!(removed.ranges().len(), 2);
        assert_eq!(set.ranges(), vec![range]);
        assert!(YrsIdSet::from_ranges(vec![YrsIdRange { client_id: 1 << 53, clock: 0, length: 1 }]).is_err());
        assert!(YrsIdSet::from_ranges(vec![YrsIdRange { client_id: 0, clock: u32::MAX, length: 1 }]).is_err());
        assert!(set.equals(&YrsIdSet::decode_v1(set.encode_v1()).unwrap()));
        assert!(set.equals(&YrsIdSet::decode_v2(set.encode_v2()).unwrap()));
    }

    #[test]
    fn malformed_set_encodings_return_errors() {
        for (client, clock, length) in [(1u64 << 53, 0, 1u32), (1, u32::MAX, 1)] {
            let mut encoder = EncoderV1::new();
            encoder.write_var(1u32);
            encoder.write_var(client);
            encoder.write_var(1u32);
            encoder.write_var(clock);
            encoder.write_var(length);
            assert!(YrsIdSet::decode_v1(encoder.to_vec()).is_err());
        }
        let mut encoder = EncoderV2::new();
        encoder.write_var(1u32);
        encoder.write_var(1u64);
        encoder.write_var(1u32);
        encoder.write_var(u32::MAX);
        encoder.write_var(0u32); // V2 encodes a length of one as zero.
        assert!(YrsIdSet::decode_v2(encoder.to_vec()).is_err());
    }

    #[test]
    fn malformed_range_order_and_v2_deltas_return_errors() {
        for ranges in [vec![(0u32, 0u32)], vec![(5, 2), (2, 1)], vec![(2, 5), (4, 5)]] {
            let mut encoder = EncoderV1::new();
            encoder.write_var(1u32);
            encoder.write_var(1u64);
            encoder.write_var(ranges.len() as u32);
            for (clock, length) in ranges {
                encoder.write_var(clock);
                encoder.write_var(length);
            }
            assert!(YrsIdSet::decode_v1(encoder.to_vec()).is_err());
        }
        for ranges in [vec![(0u32, u32::MAX)], vec![(0, 0), (u32::MAX, 0)]] {
            let mut encoder = EncoderV2::new();
            encoder.write_var(1u32);
            encoder.write_var(1u64);
            encoder.write_var(ranges.len() as u32);
            for (clock_delta, length_delta) in ranges {
                encoder.write_var(clock_delta);
                encoder.write_var(length_delta);
            }
            assert!(YrsIdSet::decode_v2(encoder.to_vec()).is_err());
        }
    }
}
