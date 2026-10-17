use crate::id_set::{client_id, YrsIdError, YrsIdRange, YrsIdSet};
use std::sync::Arc;
use yrs::updates::{decoder::Decode, encoder::Encode};
use yrs::{ContentAttribute, Diff, IdMap, ID};

pub struct YrsIdAttribute {
    pub name: String,
    pub value: String,
}

pub struct YrsIdMapRange {
    pub attributes: Vec<YrsIdAttribute>,
    pub range: YrsIdRange,
}

/// Annotation values are JSON strings, matching YSwift's Codable value transport.
pub(crate) struct YrsIdMap(IdMap<String>);

fn attributes(values: Vec<YrsIdAttribute>) -> Vec<ContentAttribute<String>> {
    values.into_iter().map(|value| ContentAttribute::new(value.name, value.value)).collect()
}

impl YrsIdMap {
    pub(crate) fn new() -> Self { Self(IdMap::new()) }

    pub(crate) fn from_ranges(ranges: Vec<YrsIdMapRange>) -> Result<Self, YrsIdError> {
        let mut map = IdMap::new();
        for entry in ranges {
            map.insert(entry.range.block_range()?, attributes(entry.attributes));
        }
        Ok(Self(map))
    }

    pub(crate) fn from_set(set: &YrsIdSet, values: Vec<YrsIdAttribute>) -> Self {
        Self(IdMap::from_set(set.0.clone(), attributes(values)))
    }

    pub(crate) fn decode_v1(data: Vec<u8>) -> Result<Self, YrsIdError> {
        IdMap::decode_v1(&data).map(Self).map_err(|_| YrsIdError::DecodingError)
    }

    pub(crate) fn decode_v2(data: Vec<u8>) -> Result<Self, YrsIdError> {
        IdMap::decode_v2(&data).map(Self).map_err(|_| YrsIdError::DecodingError)
    }

    pub(crate) fn encode_v1(&self) -> Vec<u8> { self.0.encode_v1() }
    pub(crate) fn encode_v2(&self) -> Vec<u8> { self.0.encode_v2() }
    pub(crate) fn is_empty(&self) -> bool { self.0.is_empty() }
    pub(crate) fn equals(&self, other: &Self) -> bool { self.0 == other.0 }

    pub(crate) fn contains(&self, client: u64, clock: u32) -> Result<bool, YrsIdError> {
        Ok(self.0.contains(&ID::new(client_id(client)?, clock)))
    }

    pub(crate) fn ranges(&self) -> Vec<YrsIdMapRange> {
        self.0.iter().map(|(client, entry)| YrsIdMapRange {
            attributes: entry.attrs.iter().map(|a| YrsIdAttribute { name: a.name().to_owned(), value: a.value().clone() }).collect(),
            range: YrsIdRange { client_id: client.get(), clock: entry.range.start, length: entry.range.end - entry.range.start },
        }).collect()
    }

    pub(crate) fn attributions(&self, range: YrsIdRange) -> Result<Vec<YrsIdMapRange>, YrsIdError> {
        let block = range.block_range()?;
        Ok(self.0.attributions(&block).into_iter().map(|entry| YrsIdMapRange {
            attributes: entry.attrs.iter().map(|a| YrsIdAttribute { name: a.name().to_owned(), value: a.value().clone() }).collect(),
            range: YrsIdRange { client_id: range.client_id, clock: entry.range.start, length: entry.range.end - entry.range.start },
        }).collect())
    }

    pub(crate) fn as_id_set(&self) -> Arc<YrsIdSet> { Arc::new(YrsIdSet(self.0.as_id_set())) }

    pub(crate) fn with_range(&self, values: Vec<YrsIdAttribute>, range: YrsIdRange) -> Result<Arc<Self>, YrsIdError> {
        let range = range.block_range()?;
        let mut map = self.0.clone();
        map.insert(range, attributes(values));
        Ok(Arc::new(Self(map)))
    }

    pub(crate) fn without_range(&self, range: YrsIdRange) -> Result<Arc<Self>, YrsIdError> {
        let range = range.block_range()?;
        let mut map = self.0.clone();
        map.remove(&range);
        Ok(Arc::new(Self(map)))
    }

    pub(crate) fn union(&self, other: &Self) -> Arc<Self> {
        let mut map = self.0.clone();
        map.merge_with(other.0.clone());
        Arc::new(Self(map))
    }

    pub(crate) fn intersection(&self, other: &Self) -> Arc<Self> {
        let mut map = self.0.clone();
        map.intersect_with(&other.0);
        Arc::new(Self(map))
    }

    pub(crate) fn difference(&self, other: &Self) -> Arc<Self> {
        let mut map = self.0.clone();
        map.diff_with(&other.0);
        Arc::new(Self(map))
    }

    pub(crate) fn difference_set(&self, other: &YrsIdSet) -> Arc<Self> {
        let mut map = self.0.clone();
        map.diff_with(&other.0);
        Arc::new(Self(map))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use yrs::encoding::write::Write;
    use yrs::updates::encoder::{Encoder, EncoderV1};

    #[test]
    fn overlapping_attributions_round_trip_without_mutating_inputs() {
        let set = YrsIdSet::from_ranges(vec![YrsIdRange { client_id: 7, clock: 2, length: 6 }]).unwrap();
        let first = YrsIdMap::from_set(&set, vec![YrsIdAttribute { name: "author".into(), value: "\"Alice\"".into() }]);
        let combined = first.with_range(vec![YrsIdAttribute { name: "author".into(), value: "\"Bob\"".into() }], YrsIdRange { client_id: 7, clock: 5, length: 5 }).unwrap();
        assert_eq!(first.ranges().len(), 1);
        assert_eq!(combined.ranges()[1].attributes.len(), 2);
        assert!(combined.equals(&YrsIdMap::decode_v1(combined.encode_v1()).unwrap()));
        assert!(combined.equals(&YrsIdMap::decode_v2(combined.encode_v2()).unwrap()));
    }

    #[test]
    fn malformed_attribution_indices_and_ranges_return_errors() {
        for (client, clock, length, attribute, name) in [
            (1u64 << 53, 0, 1u32, 0u32, 0u32),
            (1, u32::MAX, 1, 0, 0),
            (1, 0, 1, 4, 0),
            (1, 0, 1, 0, 4),
        ] {
            let mut encoder = EncoderV1::new();
            encoder.write_var(1u32);
            encoder.write_var(client);
            encoder.write_var(1u32);
            encoder.write_var(clock);
            encoder.write_var(length);
            encoder.write_var(1u32);
            encoder.write_var(attribute);
            encoder.write_var(name);
            encoder.write_string("author");
            encoder.write_any(&yrs::Any::String("\"Alice\"".into()));
            assert!(YrsIdMap::decode_v1(encoder.to_vec()).is_err());
        }
    }

    #[test]
    fn malformed_client_deltas_and_range_order_return_errors() {
        let mut encoder = EncoderV1::new();
        encoder.write_var(2u32);
        encoder.write_var(1u64);
        encoder.write_var(0u32);
        encoder.write_var(u64::MAX);
        assert!(YrsIdMap::decode_v1(encoder.to_vec()).is_err());

        for ranges in [vec![(0u32, 0u32)], vec![(5, 2), (2, 1)], vec![(2, 5), (4, 5)]] {
            let mut encoder = EncoderV1::new();
            encoder.write_var(1u32);
            encoder.write_var(1u64);
            encoder.write_var(ranges.len() as u32);
            for (clock, length) in ranges {
                encoder.write_var(clock);
                encoder.write_var(length);
                encoder.write_var(0u32);
            }
            assert!(YrsIdMap::decode_v1(encoder.to_vec()).is_err());
        }
    }
}
