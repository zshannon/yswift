#[derive(Debug, thiserror::Error)]
pub enum CodingError {
    #[error("EncodingError")]
    EncodingError,
    #[error("DecodingError")]
    DecodingError,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum YrsDocumentError {
    #[error("Destroy a subdocument using its parent's transaction")]
    ParentTransactionRequired,
    #[error("A document transaction is already active")]
    PendingTransaction,
}
