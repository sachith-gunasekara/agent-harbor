# Integration Testing with Mocks

## Overview

Integration tests with mocks validate the interaction between multiple components while keeping infrastructure dependencies mocked. These tests are faster than full integration tests but still verify that components work together correctly.

## Use Cases

| Scenario | What to Mock |
|----------|--------------|
| API route testing | Use cases, services |
| Use case orchestration | Repositories, external clients |
| Service layer testing | Repositories |

---

## Testing FastAPI Routes

Use `TestClient` or `httpx.AsyncClient` to test API routes with mocked use cases.

```python
# tests/integrations/api/books/test_borrow_routes.py
import pytest
from unittest.mock import Mock, AsyncMock
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.books.routes import router
from app.api.books.dependencies import get_borrow_book_use_case
from app.usecases.borrowers.borrow_book import (
    BorrowBookUseCase,
    BookNotFoundError,
    BookNotAvailableError,
)
from app.domain.entities.book import Book

@pytest.fixture
def mock_use_case() -> Mock:
    """Create a mock use case."""
    return Mock(spec=BorrowBookUseCase)

@pytest.fixture
def app(mock_use_case: Mock) -> FastAPI:
    """Create test application with mocked dependencies."""
    app = FastAPI()
    app.include_router(router)
    
    # Override dependency
    def get_mock_use_case():
        return mock_use_case
    
    app.dependency_overrides[get_borrow_book_use_case] = get_mock_use_case
    return app

@pytest.fixture
def client(app: FastAPI) -> TestClient:
    """Create test client."""
    return TestClient(app)

class TestBorrowBookRoute:
    """Integration tests for borrow book API route."""
    
    def test_borrow_book_returns_200_on_success(
        self,
        client: TestClient,
        mock_use_case: Mock,
    ):
        """Test successful book borrowing."""
        # Arrange
        borrowed_book = Book(
            id="book-123",
            title="Clean Code",
            author="Robert Martin",
            isbn="978-0132350884",
            available=False,
            borrower_id="user-456",
            revision_id=2,
        )
        mock_use_case.book = borrowed_book
        
        # Act
        response = client.post(
            "/books/book-123/borrow",
            params={"borrower_id": "user-456"}
        )
        
        # Assert
        assert response.status_code == 200
        assert response.json()["book_id"] == "book-123"
        mock_use_case.set_book_id.assert_called_with("book-123")
        mock_use_case.set_borrower_id.assert_called_with("user-456")
        mock_use_case.execute.assert_called_once()
    
    def test_borrow_book_returns_404_when_not_found(
        self,
        client: TestClient,
        mock_use_case: Mock,
    ):
        """Test 404 when book doesn't exist."""
        # Arrange
        mock_use_case.execute.side_effect = BookNotFoundError("unknown")
        
        # Act
        response = client.post(
            "/books/unknown/borrow",
            params={"borrower_id": "user-456"}
        )
        
        # Assert
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()
    
    def test_borrow_book_returns_409_when_unavailable(
        self,
        client: TestClient,
        mock_use_case: Mock,
    ):
        """Test 409 when book is already borrowed."""
        # Arrange
        mock_use_case.execute.side_effect = BookNotAvailableError("book-123")
        
        # Act
        response = client.post(
            "/books/book-123/borrow",
            params={"borrower_id": "user-456"}
        )
        
        # Assert
        assert response.status_code == 409
        assert "not available" in response.json()["detail"].lower()
```

---

## Testing with Async Client

For async routes, use `httpx.AsyncClient`:

```python
# tests/integrations/api/books/test_borrow_routes_async.py
import pytest
from httpx import AsyncClient, ASGITransport
from fastapi import FastAPI

@pytest.fixture
async def async_client(app: FastAPI) -> AsyncClient:
    """Create async test client."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

class TestBorrowBookRouteAsync:
    """Async integration tests for borrow book API."""
    
    @pytest.mark.asyncio
    async def test_borrow_book_async(
        self,
        async_client: AsyncClient,
        mock_use_case: Mock,
    ):
        """Test borrowing with async client."""
        mock_use_case.book = Book(...)
        
        response = await async_client.post(
            "/books/book-123/borrow",
            params={"borrower_id": "user-456"}
        )
        
        assert response.status_code == 200
```

---

## Testing Request/Response Validation

Verify that Pydantic models correctly validate and serialize data:

```python
class TestRequestValidation:
    """Test request validation."""
    
    def test_invalid_book_id_returns_422(self, client: TestClient):
        """Test validation error for invalid input."""
        response = client.post(
            "/books//borrow",  # Empty book_id
            params={"borrower_id": "user-456"}
        )
        
        assert response.status_code == 422
    
    def test_missing_borrower_id_returns_422(self, client: TestClient):
        """Test validation error for missing required field."""
        response = client.post("/books/book-123/borrow")
        
        assert response.status_code == 422
```

---

## Using Dependency Overrides

FastAPI's `dependency_overrides` allows replacing dependencies for testing:

```python
from fastapi import FastAPI, Depends

app = FastAPI()

# Production dependency
def get_repository() -> BookRepositoryInterface:
    return SQLAlchemyBookRepository(session)

# Override for testing
def get_mock_repository() -> Mock:
    return Mock(spec=BookRepositoryInterface)

# Apply override
app.dependency_overrides[get_repository] = get_mock_repository
```

---

## Running Integration Tests with Mocks

```bash
# Run all integration tests
pytest tests/integrations/

# Run API tests only
pytest tests/integrations/api/

# Run with verbose output
pytest tests/integrations/ -v

# Run in parallel
pytest tests/integrations/ -n auto
```
