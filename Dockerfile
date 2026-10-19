# --- Stage 1: build ---
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish

# --- Stage 2: runtime ---
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
# Pull list of available packages
RUN apt-get update \
# Download latest versions of required packages
    && apt-get upgrade -y\
# Download and install curl and only required packages
    && apt-get install -y --no-install-recommends curl \
# Remove list of available packages
    && rm -rf /var/lib/apt/lists/* \
    && adduser --disabled-password --gecos "" appuser
COPY --from=build /app/publish .
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8080/health || exit 1
ENTRYPOINT [ "dotnet", "OrderService.dll" ]