# Integration Testing with Testcontainers

## Overview

Integration tests with testcontainers validate that infrastructure implementations work correctly with real resources. These tests use Docker containers to spin up real databases, message queues, and other services.

## When to Use

| Use Case | Description |
|----------|-------------|
| **Repository validation** | Test SQL queries and ORM mappings |
| **Database migrations** | Verify migrations run correctly |
| **External service integration** | Test real API interactions |
| **Performance validation** | Benchmark with real infrastructure |

---

## Installing Testcontainers

```bash
poetry add --group dev testcontainers
```

Available modules:
- `testcontainers[postgres]`
- `testcontainers[mysql]`
- `testcontainers[redis]`
- `testcontainers[mongodb]`
- `testcontainers[kafka]`
- `testcontainers[rabbitmq]`

---

## PostgreSQL Example

```python
# tests/integrations/persistence/test_book_repository.py
import pytest
from testcontainers.postgres import PostgresContainer
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

from app.persistence.models.book_model import BookModel, Base
from app.persistence.repositories.book_repository import SQLAlchemyBookRepository
from app.domain.entities.book import Book

@pytest.fixture(scope="module")
def postgres_container():
    """Start PostgreSQL container for the test module."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

@pytest.fixture(scope="module")
def engine(postgres_container):
    """Create SQLAlchemy engine connected to test container."""
    engine = create_engine(postgres_container.get_connection_url())
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)

@pytest.fixture
def session(engine) -> Session:
    """Create a new session for each test."""
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.rollback()
    session.close()

@pytest.fixture
def repository(session: Session) -> SQLAlchemyBookRepository:
    """Create repository with test session."""
    return SQLAlchemyBookRepository(session)

class TestSQLAlchemyBookRepository:
    """Integration tests for book repository with real PostgreSQL."""
    
    def test_save_and_find_book(self, repository: SQLAlchemyBookRepository, session: Session):
        """Test saving and retrieving a book."""
        # Arrange
        book = Book(
            id="book-123",
            title="Clean Code",
            author="Robert Martin",
            isbn="978-0132350884",
            available=True,
            borrower_id=None,
            revision_id=0,
        )
        
        # Act
        saved_book = repository.save(book)
        session.commit()
        
        found_book = repository.find_by_id("book-123")
        
        # Assert
        assert found_book is not None
        assert found_book.id == "book-123"
        assert found_book.title == "Clean Code"
        assert saved_book.revision_id == 1
    
    def test_find_nonexistent_book_returns_none(
        self,
        repository: SQLAlchemyBookRepository,
    ):
        """Test finding a book that doesn't exist."""
        result = repository.find_by_id("nonexistent")
        
        assert result is None
    
    def test_update_book_increments_revision(
        self,
        repository: SQLAlchemyBookRepository,
        session: Session,
    ):
        """Test that updating a book increments revision_id."""
        # Arrange
        book = Book(
            id="book-456",
            title="Test Book",
            author="Author",
            isbn="123-456",
            available=True,
            revision_id=0,
        )
        saved_book = repository.save(book)
        session.commit()
        
        # Act
        updated_book = saved_book.model_copy(update={"available": False})
        result = repository.save(updated_book)
        session.commit()
        
        # Assert
        assert result.revision_id == 2
        assert result.available is False
```

---

## Using Fixtures with Module Scope

For expensive container startup, use module or session scope:

```python
@pytest.fixture(scope="module")
def postgres_container():
    """Container shared across all tests in module."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

@pytest.fixture(scope="function")
def session(engine):
    """Fresh session for each test with rollback."""
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.rollback()
    session.close()
```

---

## Redis Example

```python
# tests/integrations/external/test_cache_client.py
import pytest
from testcontainers.redis import RedisContainer

from app.external.cache_client import RedisCacheClient

@pytest.fixture(scope="module")
def redis_container():
    """Start Redis container."""
    with RedisContainer("redis:7-alpine") as redis:
        yield redis

@pytest.fixture
def cache_client(redis_container) -> RedisCacheClient:
    """Create cache client connected to test container."""
    return RedisCacheClient(
        host=redis_container.get_container_host_ip(),
        port=redis_container.get_exposed_port(6379),
    )

class TestRedisCacheClient:
    """Integration tests for Redis cache client."""
    
    def test_set_and_get_value(self, cache_client: RedisCacheClient):
        """Test setting and getting a cached value."""
        cache_client.set("key", "value", ttl=60)
        
        result = cache_client.get("key")
        
        assert result == "value"
    
    def test_get_nonexistent_key_returns_none(self, cache_client: RedisCacheClient):
        """Test getting a key that doesn't exist."""
        result = cache_client.get("nonexistent")
        
        assert result is None
```

---

## MongoDB Example

```python
# tests/integrations/persistence/test_mongo_repository.py
import pytest
from testcontainers.mongodb import MongoDbContainer

@pytest.fixture(scope="module")
def mongo_container():
    """Start MongoDB container."""
    with MongoDbContainer("mongo:7") as mongo:
        yield mongo

@pytest.fixture
def mongo_client(mongo_container):
    """Create MongoDB client."""
    from pymongo import MongoClient
    return MongoClient(mongo_container.get_connection_url())
```

---

## Testing Database Migrations

```python
# tests/integrations/persistence/test_migrations.py
import pytest
from testcontainers.postgres import PostgresContainer
from alembic.config import Config
from alembic import command

@pytest.fixture(scope="module")
def postgres_container():
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

def test_migrations_run_successfully(postgres_container):
    """Test that all migrations can be applied."""
    alembic_cfg = Config("alembic.ini")
    alembic_cfg.set_main_option(
        "sqlalchemy.url",
        postgres_container.get_connection_url()
    )
    
    # Run all migrations
    command.upgrade(alembic_cfg, "head")
    
    # Verify by downgrading
    command.downgrade(alembic_cfg, "base")
```

---

## Conftest Setup

Centralize container fixtures in `conftest.py`:

```python
# tests/integrations/conftest.py
import pytest
from testcontainers.postgres import PostgresContainer
from testcontainers.redis import RedisContainer

@pytest.fixture(scope="session")
def postgres_container():
    """PostgreSQL container shared across all integration tests."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

@pytest.fixture(scope="session")
def redis_container():
    """Redis container shared across all integration tests."""
    with RedisContainer("redis:7-alpine") as redis:
        yield redis
```

---

## Running Integration Tests with Containers

```bash
# Run all container-based tests (requires Docker)
pytest tests/integrations/persistence/ -v

# Run with specific marker
pytest -m "integration" -v

# Skip container tests in CI without Docker
pytest tests/integrations/ --ignore=tests/integrations/persistence/
```

---

## Best Practices

| Practice | Description |
|----------|-------------|
| **Use module/session scope** | Minimize container startup time |
| **Rollback after each test** | Keep tests isolated |
| **Use lightweight images** | Alpine variants are faster |
| **Clean up resources** | Use context managers |
| **Mark tests appropriately** | Use `@pytest.mark.integration` |

---

## External References

| Document | Description |
|----------|-------------|
| [testcontainers-python](https://testcontainers-python.readthedocs.io/) | Official documentation |
| [Available Modules](https://testcontainers-python.readthedocs.io/en/latest/modules.html) | Supported containers |
