# Unit Testing

## Overview

Unit tests validate individual components in isolation. All external dependencies are mocked to ensure tests are fast, deterministic, and focused on the component under test.

## Principles

| Principle | Description |
|-----------|-------------|
| **Isolation** | Test one unit at a time, mock all dependencies |
| **Fast** | No I/O operations, execute in milliseconds |
| **Deterministic** | Same input always produces same output |
| **Readable** | Clear arrange-act-assert structure |

---

## Fixtures

Use fixtures with **functional meaning** to make tests readable and refactoring easy. Instead of creating test data inline, use centralized fixtures named by their business state (e.g., `book_available`, `book_borrowed`, `user_activated`, `user_deactivated`).

For detailed patterns on fixture organization, factories, and `conftest.py` setup, see [Test Fixtures](test-fixtures.md).

---

## Testing Use Cases

Use cases are ideal candidates for unit testing because dependencies are injected.

```python
# tests/units/usecases/borrowers/test_borrow_book.py
import pytest
from unittest.mock import Mock

from app.domain.entities.book import Book
from app.usecases.borrowers.borrow_book import (
    BorrowBookUseCase,
    BookRepositoryInterface,
    BookNotFoundError,
    BookNotAvailableError,
)

class TestBorrowBookUseCase:
    """Unit tests for BorrowBookUseCase."""
    
    @pytest.fixture
    def mock_repository(self) -> Mock:
        """Create a mock repository."""
        return Mock(spec=BookRepositoryInterface)
    
    @pytest.fixture
    def use_case(self, mock_repository: Mock) -> BorrowBookUseCase:
        """Create use case with mocked dependencies."""
        return BorrowBookUseCase(repository=mock_repository)
    
    @pytest.fixture
    def available_book(self) -> Book:
        """Create an available book for testing."""
        return Book(
            id="book-123",
            title="Clean Code",
            author="Robert Martin",
            isbn="978-0132350884",
            available=True,
            borrower_id=None,
            revision_id=1,
        )
    
    def test_borrow_available_book_succeeds(
        self,
        use_case: BorrowBookUseCase,
        mock_repository: Mock,
        available_book: Book,
    ):
        """Test borrowing an available book."""
        # Arrange
        mock_repository.find_by_id.return_value = available_book
        mock_repository.save.return_value = available_book.model_copy(
            update={"available": False, "borrower_id": "user-456", "revision_id": 2}
        )
        
        # Act
        result = use_case.borrow(book_id="book-123", borrower_id="user-456")
        
        # Assert
        assert result.available is False
        assert result.borrower_id == "user-456"
        assert result.revision_id == 2
        mock_repository.find_by_id.assert_called_once_with("book-123")
        mock_repository.save.assert_called_once()
    
    def test_borrow_nonexistent_book_raises_error(
        self,
        use_case: BorrowBookUseCase,
        mock_repository: Mock,
    ):
        """Test borrowing a book that doesn't exist."""
        # Arrange
        mock_repository.find_by_id.return_value = None
        
        # Act & Assert
        with pytest.raises(BookNotFoundError) as exc_info:
            use_case.borrow(book_id="unknown", borrower_id="user-456")
        
        assert exc_info.value.book_id == "unknown"
    
    def test_borrow_unavailable_book_raises_error(
        self,
        use_case: BorrowBookUseCase,
        mock_repository: Mock,
        available_book: Book,
    ):
        """Test borrowing a book that is already borrowed."""
        # Arrange
        unavailable_book = available_book.model_copy(
            update={"available": False, "borrower_id": "other-user"}
        )
        mock_repository.find_by_id.return_value = unavailable_book
        
        # Act & Assert
        with pytest.raises(BookNotAvailableError) as exc_info:
            use_case.borrow(book_id="book-123", borrower_id="user-456")
        
        assert exc_info.value.book_id == "book-123"
        mock_repository.save.assert_not_called()
```

---

## Testing Domain Entities

Domain entities contain business logic that should be unit tested.

```python
# tests/units/domain/entities/test_book.py
import pytest
from app.domain.entities.book import Book

class TestBook:
    """Unit tests for Book entity."""
    
    def test_available_book_can_be_borrowed(self):
        """Test that available book can be borrowed."""
        book = Book(
            id="123",
            title="Test",
            author="Author",
            isbn="123-456",
            available=True,
        )
        
        assert book.is_available_for_borrowing() is True
    
    def test_unavailable_book_cannot_be_borrowed(self):
        """Test that unavailable book cannot be borrowed."""
        book = Book(
            id="123",
            title="Test",
            author="Author",
            isbn="123-456",
            available=False,
        )
        
        assert book.is_available_for_borrowing() is False
```

---

## Testing Pure Functional Methods

Test each functional method independently:

```python
class TestBorrowBookUseCaseMethods:
    """Test individual methods of BorrowBookUseCase."""
    
    def test_retrieve_book_returns_book_when_found(
        self,
        use_case: BorrowBookUseCase,
        mock_repository: Mock,
        available_book: Book,
    ):
        """Test retrieve_book method."""
        mock_repository.find_by_id.return_value = available_book
        
        result = use_case.retrieve_book("book-123")
        
        assert result == available_book
    
    def test_borrow_book_creates_immutable_copy(
        self,
        use_case: BorrowBookUseCase,
        mock_repository: Mock,
        available_book: Book,
    ):
        """Test borrow_book method creates new entity."""
        mock_repository.save.return_value = available_book.model_copy(
            update={"available": False, "borrower_id": "user-456"}
        )
        
        result = use_case.borrow_book(available_book, "user-456")
        
        # Original entity unchanged
        assert available_book.available is True
        # New entity has updates
        assert result.available is False
        assert result.borrower_id == "user-456"
```

---

## Mocking Best Practices

### Use `spec` Parameter

Always use `spec` to ensure mocks match the interface:

```python
mock_repo = Mock(spec=BookRepositoryInterface)
```

### Verify Interactions

Use assertions to verify mock calls:

```python
mock_repo.find_by_id.assert_called_once_with("book-123")
mock_repo.save.assert_called_once()
mock_repo.save.assert_not_called()
```

### Use `side_effect` for Exceptions

```python
mock_repo.find_by_id.side_effect = DatabaseConnectionError("Connection failed")
```

### Use `return_value` for Simple Returns

```python
mock_repo.find_by_id.return_value = book
```

---

## Running Unit Tests

```bash
# Run all unit tests
pytest tests/units/

# Run with coverage
pytest tests/units/ --cov=app --cov-report=html

# Run in parallel
pytest tests/units/ -n auto

# Run specific test file
pytest tests/units/usecases/borrowers/test_borrow_book.py

# Run specific test
pytest tests/units/usecases/borrowers/test_borrow_book.py::TestBorrowBookUseCase::test_borrow_available_book_succeeds
```
