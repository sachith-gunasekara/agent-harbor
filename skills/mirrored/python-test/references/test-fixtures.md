# Test Fixtures

## Overview

Test fixtures provide reusable test data and setup.
You can use fixtures with **functional meaning** (e.g., `user_activated`, `user_deactivated`) to make tests more readable and refactoring easier.

## Principles

| Principle | Description |
|-----------|-------------|
| **Functional Naming** | Name fixtures by their business state, not structure |
| **Single Responsibility** | Each fixture represents one specific state |
| **Composability** | Build complex fixtures from simpler ones |
| **Centralized** | Define in dedicated modules, import via `conftest.py` |

---

## Fixture Organization

```
tests/
|-- conftest.py                    # Import and expose all fixtures
|-- fixtures/
|   |-- __init__.py                # Export fixtures with __all__
|   |-- book_fixtures.py           # Book-related fixtures
|   |-- user_fixtures.py           # User-related fixtures
|   |-- repository_fixtures.py     # Mock repository fixtures
```

---

## Fixtures with Functional Meaning

Create fixtures that represent specific business states:

```python
# tests/fixtures/user_fixtures.py
import pytest
from app.domain.entities.user import User

__all__ = [
    "user_activated",
    "user_deactivated",
    "user_admin",
    "user_with_expired_subscription",
    "user_factory",
]

@pytest.fixture
def user_activated() -> User:
    """An active user who can perform actions."""
    return User(
        id="user-123",
        email="active@example.com",
        name="Active User",
        is_active=True,
        role="member",
    )

@pytest.fixture
def user_deactivated() -> User:
    """A deactivated user who cannot perform actions."""
    return User(
        id="user-456",
        email="inactive@example.com",
        name="Inactive User",
        is_active=False,
        role="member",
    )

@pytest.fixture
def user_admin() -> User:
    """An admin user with elevated privileges."""
    return User(
        id="admin-001",
        email="admin@example.com",
        name="Admin User",
        is_active=True,
        role="admin",
    )

@pytest.fixture
def user_with_expired_subscription() -> User:
    """A user whose subscription has expired."""
    from datetime import datetime, timedelta
    return User(
        id="user-789",
        email="expired@example.com",
        name="Expired User",
        is_active=True,
        role="member",
        subscription_expires_at=datetime.now() - timedelta(days=30),
    )
```

```python
# tests/fixtures/book_fixtures.py
import pytest
from app.domain.entities.book import Book

__all__ = [
    "book_available",
    "book_borrowed",
    "book_reserved",
    "book_out_of_stock",
    "book_factory",
]

@pytest.fixture
def book_available() -> Book:
    """A book available for borrowing."""
    return Book(
        id="book-001",
        title="Clean Code",
        author="Robert Martin",
        isbn="978-0132350884",
        available=True,
        borrower_id=None,
        revision_id=1,
    )

@pytest.fixture
def book_borrowed() -> Book:
    """A book currently borrowed by a user."""
    return Book(
        id="book-002",
        title="Domain-Driven Design",
        author="Eric Evans",
        isbn="978-0321125217",
        available=False,
        borrower_id="user-123",
        revision_id=2,
    )

@pytest.fixture
def book_reserved() -> Book:
    """A book that has been reserved."""
    return Book(
        id="book-003",
        title="Refactoring",
        author="Martin Fowler",
        isbn="978-0134757599",
        available=False,
        borrower_id=None,
        reserved_by="user-456",
        revision_id=1,
    )

@pytest.fixture
def book_out_of_stock() -> Book:
    """A book that is out of stock (no copies available)."""
    return Book(
        id="book-004",
        title="The Pragmatic Programmer",
        author="David Thomas",
        isbn="978-0135957059",
        available=False,
        borrower_id=None,
        stock_count=0,
        revision_id=1,
    )
```

---

## Fixture Factories

For cases where you need customization, provide factory fixtures:

```python
# tests/fixtures/book_fixtures.py
from typing import Callable

@pytest.fixture
def book_factory() -> Callable[..., Book]:
    """
    Factory for creating books with custom attributes.
    
    Use when you need specific values not covered by semantic fixtures.
    """
    def _create_book(
        id: str = "book-factory-001",
        title: str = "Factory Book",
        author: str = "Factory Author",
        isbn: str = "000-000-000",
        available: bool = True,
        borrower_id: str | None = None,
        revision_id: int = 1,
        **kwargs,
    ) -> Book:
        return Book(
            id=id,
            title=title,
            author=author,
            isbn=isbn,
            available=available,
            borrower_id=borrower_id,
            revision_id=revision_id,
            **kwargs,
        )
    return _create_book

# Usage in tests:
def test_with_factory(book_factory):
    # Create multiple books with specific attributes
    book1 = book_factory(id="custom-1", title="Custom Book 1")
    book2 = book_factory(id="custom-2", available=False)
```

---

## Mock Repository Fixtures

```python
# tests/fixtures/repository_fixtures.py
import pytest
from unittest.mock import Mock

from app.usecases.borrowers.borrow_book import BookRepositoryInterface
from app.usecases.users.user_repository import UserRepositoryInterface

__all__ = [
    "mock_book_repository",
    "mock_user_repository",
]

@pytest.fixture
def mock_book_repository() -> Mock:
    """Mock book repository for use case testing."""
    return Mock(spec=BookRepositoryInterface)

@pytest.fixture
def mock_user_repository() -> Mock:
    """Mock user repository for use case testing."""
    return Mock(spec=UserRepositoryInterface)
```

---

## In-Memory Repository Fixtures

For more realistic testing without external dependencies, use in-memory implementations:

```python
# tests/fixtures/infrastructure_fixtures.py
import pytest
from typing import Dict

from app.domain.entities.book import Book
from app.usecases.borrowers.borrow_book import BookRepositoryInterface

__all__ = [
    "in_memory_book_repository",
    "in_memory_book_repository_with_books",
]

class InMemoryBookRepository(BookRepositoryInterface):
    """In-memory implementation of BookRepositoryInterface for testing."""
    
    def __init__(self):
        self._books: Dict[str, Book] = {}
        self._revision_counter: int = 0
    
    def find_by_id(self, book_id: str) -> Book | None:
        return self._books.get(book_id)
    
    def find_all(self) -> list[Book]:
        return list(self._books.values())
    
    def save(self, book: Book) -> Book:
        self._revision_counter += 1
        saved_book = book.model_copy(update={"revision_id": self._revision_counter})
        self._books[saved_book.id] = saved_book
        return saved_book
    
    def delete(self, book_id: str) -> None:
        self._books.pop(book_id, None)
    
    # Test helpers
    def seed(self, books: list[Book]) -> None:
        """Seed repository with test data."""
        for book in books:
            self._books[book.id] = book
    
    def clear(self) -> None:
        """Clear all data."""
        self._books.clear()
        self._revision_counter = 0

@pytest.fixture
def in_memory_book_repository() -> InMemoryBookRepository:
    """Empty in-memory book repository."""
    return InMemoryBookRepository()

@pytest.fixture
def in_memory_book_repository_with_books(
    in_memory_book_repository: InMemoryBookRepository,
    book_available: Book,
    book_borrowed: Book,
) -> InMemoryBookRepository:
    """In-memory repository pre-seeded with test books."""
    in_memory_book_repository.seed([book_available, book_borrowed])
    return in_memory_book_repository
```

---

## Mocked External API Fixtures

For testing components that depend on external APIs:

```python
# tests/fixtures/api_client_fixtures.py
import pytest
from unittest.mock import Mock, AsyncMock
from typing import Any

__all__ = [
    "mock_payment_api",
    "mock_notification_api",
    "mock_http_client",
]

@pytest.fixture
def mock_payment_api() -> Mock:
    """
    Mock payment API client.
    
    Pre-configured with common successful responses.
    """
    mock = Mock()
    
    # Configure default successful responses
    mock.create_charge.return_value = {
        "id": "charge-001",
        "status": "succeeded",
        "amount": 1000,
        "currency": "usd",
    }
    mock.refund.return_value = {
        "id": "refund-001",
        "status": "succeeded",
    }
    
    return mock

@pytest.fixture
def mock_payment_api_failing() -> Mock:
    """Mock payment API that simulates failures."""
    from app.external.payment import PaymentFailedError
    
    mock = Mock()
    mock.create_charge.side_effect = PaymentFailedError("Card declined")
    return mock

@pytest.fixture
def mock_notification_api() -> AsyncMock:
    """Mock async notification API client."""
    mock = AsyncMock()
    mock.send_email.return_value = {"message_id": "msg-001", "status": "sent"}
    mock.send_sms.return_value = {"message_id": "sms-001", "status": "sent"}
    return mock

@pytest.fixture
def mock_http_client() -> Mock:
    """
    Generic mock HTTP client for external API testing.
    
    Configure responses per test as needed.
    """
    mock = Mock()
    
    # Default response
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {}
    mock.get.return_value = mock_response
    mock.post.return_value = mock_response
    
    return mock
```

---

## Fake External Services

For complex integrations, create fake implementations:

```python
# tests/fixtures/fake_services.py
import pytest
from typing import Any, Dict, List
from dataclasses import dataclass, field

from app.external.email import EmailDeliveryError

__all__ = [
    "fake_email_service",
    "fake_cache_service",
]

@dataclass
class FakeEmailService:
    """Fake email service that captures sent emails for verification."""
    
    sent_emails: List[Dict] = field(default_factory=list)
    should_fail: bool = False
    
    def send(self, to: str, subject: str, body: str) -> Dict:
        if self.should_fail:
            raise EmailDeliveryError("Failed to send email")
        
        email = {
            "to": to,
            "subject": subject,
            "body": body,
            "message_id": f"fake-{len(self.sent_emails) + 1}",
        }
        self.sent_emails.append(email)
        return email
    
    # Test helpers
    def get_emails_to(self, recipient: str) -> List[Dict]:
        """Get all emails sent to a specific recipient."""
        return [e for e in self.sent_emails if e["to"] == recipient]
    
    def clear(self) -> None:
        """Clear sent emails."""
        self.sent_emails.clear()

@dataclass
class FakeCacheService:
    """Fake cache service for testing caching behavior."""
    
    _cache: Dict[str, Any] = field(default_factory=dict)
    _ttls: Dict[str, int] = field(default_factory=dict)
    
    def get(self, key: str) -> Any | None:
        return self._cache.get(key)
    
    def set(self, key: str, value: Any, ttl: int = 3600) -> None:
        self._cache[key] = value
        self._ttls[key] = ttl
    
    def delete(self, key: str) -> None:
        self._cache.pop(key, None)
        self._ttls.pop(key, None)
    
    # Test helpers
    def get_ttl(self, key: str) -> int | None:
        """Get TTL for a key (for verification)."""
        return self._ttls.get(key)
    
    def has_key(self, key: str) -> bool:
        """Check if key exists."""
        return key in self._cache
    
    def clear(self) -> None:
        """Clear all cached data."""
        self._cache.clear()
        self._ttls.clear()

@pytest.fixture
def fake_email_service() -> FakeEmailService:
    """Fake email service for testing."""
    return FakeEmailService()

@pytest.fixture
def fake_cache_service() -> FakeCacheService:
    """Fake cache service for testing."""
    return FakeCacheService()
```

---

## Using Infrastructure Fixtures

```python
# tests/units/usecases/test_borrow_book_with_infra.py

class TestBorrowBookUseCaseWithInMemoryRepo:
    """Tests using in-memory repository."""
    
    def test_borrow_book_persists_changes(
        self,
        in_memory_book_repository_with_books: InMemoryBookRepository,
        book_available: Book,
    ):
        """Test that borrow operation persists to repository."""
        use_case = BorrowBookUseCase(in_memory_book_repository_with_books)
        
        # Act
        result = use_case.borrow(book_available.id, "user-456")
        
        # Assert - verify persistence
        persisted_book = in_memory_book_repository_with_books.find_by_id(book_available.id)
        assert persisted_book is not None
        assert persisted_book.available is False
        assert persisted_book.borrower_id == "user-456"
        assert persisted_book.revision_id > book_available.revision_id


class TestNotificationServiceWithFakeEmail:
    """Tests using fake email service."""
    
    def test_sends_confirmation_email(
        self,
        fake_email_service: FakeEmailService,
        user_activated: User,
    ):
        """Test that confirmation email is sent."""
        service = NotificationService(email_service=fake_email_service)
        
        # Act
        service.send_borrow_confirmation(user_activated, book_id="book-123")
        
        # Assert
        emails = fake_email_service.get_emails_to(user_activated.email)
        assert len(emails) == 1
        assert "confirmation" in emails[0]["subject"].lower()
    
    def test_handles_email_failure_gracefully(
        self,
        fake_email_service: FakeEmailService,
        user_activated: User,
    ):
        """Test graceful handling of email failures."""
        fake_email_service.should_fail = True
        service = NotificationService(email_service=fake_email_service)
        
        # Act & Assert - should not raise
        service.send_borrow_confirmation(user_activated, book_id="book-123")
```

---

## Updated Fixtures __init__.py

```python
# tests/fixtures/__init__.py
"""
Test fixtures module.

All fixtures are exported via __all__ for discovery by conftest.py.
"""

from tests.fixtures.book_fixtures import *
from tests.fixtures.user_fixtures import *
from tests.fixtures.repository_fixtures import *
from tests.fixtures.infrastructure_fixtures import *
from tests.fixtures.api_client_fixtures import *
from tests.fixtures.fake_services import *

__all__ = [
    # Book fixtures
    "book_available",
    "book_borrowed",
    "book_reserved",
    "book_out_of_stock",
    "book_factory",
    # User fixtures
    "user_activated",
    "user_deactivated",
    "user_admin",
    "user_with_expired_subscription",
    "user_factory",
    # Mock repository fixtures
    "mock_book_repository",
    "mock_user_repository",
    # In-memory repositories
    "in_memory_book_repository",
    "in_memory_book_repository_with_books",
    # Mock API clients
    "mock_payment_api",
    "mock_payment_api_failing",
    "mock_notification_api",
    "mock_http_client",
    # Fake services
    "fake_email_service",
    "fake_cache_service",
]
```

---

## Conftest.py Import Pattern

Import all fixtures in `conftest.py` to enable pytest discovery:

```python
# tests/conftest.py
"""
Root conftest.py - imports all fixtures for pytest discovery.

Fixtures are defined in tests/fixtures/ and imported here.
"""
import pytest

# Import all fixtures from fixtures module
from tests.fixtures import *
from tests.fixtures import __all__ as fixture_names

# Re-export for pytest discovery
__all__ = fixture_names

# --- Additional root-level fixtures ---

@pytest.fixture(autouse=True)
def reset_mocks(request):
    """Reset all mocks after each test."""
    yield
    # Cleanup logic if needed
```

For subfolders, create specific conftest files:

```python
# tests/units/conftest.py
"""Unit test fixtures."""
from tests.fixtures import *
from tests.fixtures import __all__

# Unit-specific fixtures can be added here

# tests/integrations/conftest.py
"""Integration test fixtures."""
from tests.fixtures import *
from tests.fixtures import __all__

# Add container fixtures for integration tests
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres
```

---

## Using Fixtures in Tests

```python
# tests/units/usecases/test_borrow_book.py

class TestBorrowBookUseCase:
    """Tests using semantic fixtures."""
    
    def test_borrow_available_book(
        self,
        mock_book_repository: Mock,
        book_available: Book,
        user_activated: User,
    ):
        """Test borrowing an available book by an active user."""
        # Arrange
        mock_book_repository.find_by_id.return_value = book_available
        mock_book_repository.save.return_value = book_available.model_copy(
            update={"available": False, "borrower_id": user_activated.id}
        )
        
        use_case = BorrowBookUseCase(mock_book_repository)
        
        # Act
        result = use_case.borrow(book_available.id, user_activated.id)
        
        # Assert
        assert result.available is False
        assert result.borrower_id == user_activated.id
    
    def test_cannot_borrow_already_borrowed_book(
        self,
        mock_book_repository: Mock,
        book_borrowed: Book,
        user_activated: User,
    ):
        """Test that borrowed books cannot be borrowed again."""
        mock_book_repository.find_by_id.return_value = book_borrowed
        
        use_case = BorrowBookUseCase(mock_book_repository)
        
        with pytest.raises(BookNotAvailableError):
            use_case.borrow(book_borrowed.id, user_activated.id)
    
    def test_deactivated_user_cannot_borrow(
        self,
        mock_book_repository: Mock,
        book_available: Book,
        user_deactivated: User,
    ):
        """Test that deactivated users cannot borrow books."""
        mock_book_repository.find_by_id.return_value = book_available
        
        use_case = BorrowBookUseCase(mock_book_repository)
        
        with pytest.raises(UserNotActiveError):
            use_case.borrow(book_available.id, user_deactivated.id)
```

---

## Benefits of Functional Naming

| Benefit | Description |
|---------|-------------|
| **Readability** | Test intent is clear from fixture names |
| **Refactoring** | Change fixture once, all tests update |
| **Discoverability** | Easy to find fixtures by business state |
| **Consistency** | Same state used across all tests |
| **Documentation** | Fixtures serve as examples of valid states |

---

## Best Practices

1. **Name by state, not structure** - Use `book_borrowed` not `book_with_borrower_id`
2. **One fixture per state** - Don't overload fixtures with parameters
3. **Use factories for edge cases** - When semantic fixtures don't cover the case
4. **Keep fixtures small** - Each fixture should represent one concept
5. **Document fixture purpose** - Docstrings explain the business meaning
6. **Centralize definitions** - All fixtures in `tests/fixtures/`
7. **Export via `__all__`** - Enable proper discovery and IDE support
8. **Use in-memory repos for integration** - More realistic than mocks, faster than containers
9. **Fake services capture calls** - Add helpers to verify interactions
10. **Pre-configure common responses** - Reduce boilerplate in tests
11. **Group tests in classes** - Always use test classes for context grouping; multiple classes per file allowed
