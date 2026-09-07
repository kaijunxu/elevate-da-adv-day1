import argparse
import os
import random
import string
import subprocess
import sys
import time
from google.cloud import aiplatform
from google.api_core.exceptions import NotFound


def generate_random_suffix(length: int = 6) -> str:
    """Generates a random lowercase alphanumeric string."""
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choices(chars, k=length))


def check_bq_model_exists(project_id: str, dataset_id: str, model_name: str) -> bool:
    """Checks if a BigQuery model exists in the target dataset.

    Args:
        project_id: GCP project ID.
        dataset_id: Target dataset ID.
        model_name: BigQuery model name.

    Returns:
        True if the model exists, False otherwise.
    """
    dest_model_path = f"{project_id}:{dataset_id}.{model_name}"
    cmd = f"bq show --model --project_id={project_id} {dest_model_path}"
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def check_vertex_model_exists(
    project_id: str,
    location: str,
    model_display_name: str,
) -> tuple[bool, aiplatform.Model | None]:
    """Checks if a model already exists in Vertex AI Model Registry.

    Args:
        project_id: GCP project ID.
        location: GCP region / location.
        model_display_name: Display name or resource ID of the model.

    Returns:
        A tuple of (exists: bool, model: aiplatform.Model | None).
    """
    aiplatform.init(project=project_id, location=location)
    try:
        model = aiplatform.Model(f"projects/{project_id}/locations/{location}/models/{model_display_name}")
        _ = model.resource_name
        return True, model
    except NotFound:
        return False, None


def copy_bqml_model(
    source_model_name: str,
    project_id: str,
    dataset_id: str = "cymbal_gold",
    target_model_name: str = None,
) -> str:
    """Copies BQML model from source project to target project dataset.

    Args:
        source_model_name: Name of the source BQML model.
        project_id: GCP project ID.
        dataset_id: Destination dataset ID. Defaults to "cymbal_gold".
        target_model_name: Optional destination model name. Defaults to source_model_name.

    Returns:
        The destination model path as a string.
    """
    target_name = target_model_name or source_model_name
    source_model_path = f"elevate-dev-kaijun:da_elevate_models.{source_model_name}"
    dest_model_path = f"{project_id}:{dataset_id}.{target_name}"

    print(f"Copying BQML model to '{dest_model_path}'...")
    copy_cmd = f"bq cp -f --project_id={project_id} {source_model_path} {dest_model_path}"
    subprocess.run(copy_cmd, shell=True, check=True)
    return dest_model_path


def register_bqml_model(
    model_display_name: str,
    dest_model_path: str,
    project_id: str,
    location: str = "us-central1",
) -> aiplatform.Model:
    """Registers BQML model from dest_model_path to Vertex AI Model Registry.

    Args:
        model_display_name: Display name for the registered model in Vertex AI Model Registry.
        dest_model_path: Destination BigQuery model path (project:dataset.model).
        project_id: GCP project ID.
        location: GCP region / location. Defaults to "us-central1".

    Returns:
        The registered Vertex AI Model object.
    """
    aiplatform.init(project=project_id, location=location)

    # Register the copied model to Vertex AI Model Registry
    print(f"Registering BQML model '{dest_model_path}' to Vertex AI Model Registry as '{model_display_name}'...")
    register_cmd = (
        f"bq update --model --project_id={project_id} "
        f"--vertex_ai_model_id '{model_display_name}' {dest_model_path}"
    )
    subprocess.run(register_cmd, shell=True, check=True)

    # Load the registered model with retries (due to Vertex AI registration latency)
    max_retries = 24
    retry_delay_seconds = 5
    for attempt in range(1, max_retries + 1):
        try:
            print(f"Loading registered model '{model_display_name}' (attempt {attempt}/{max_retries})...")
            model = aiplatform.Model(f"projects/{project_id}/locations/{location}/models/{model_display_name}")
            print(f"Registered Model Resource Name: {model.resource_name}")
            return model
        except NotFound as e:
            if attempt == max_retries:
                print(f"[ERROR] Model '{model_display_name}' was not found in Vertex AI Model Registry after {max_retries * retry_delay_seconds} seconds.")
                raise e
            print(f"Model not found yet. Retrying in {retry_delay_seconds} seconds...")
            time.sleep(retry_delay_seconds)


def deploy_model_to_endpoint(
    model_display_name: str,
    endpoint_id: str,
    project_id: str,
    location: str = "us-central1",
    machine_type: str = "n1-standard-2",
    register: bool = False,
    model: aiplatform.Model = None,
) -> tuple[aiplatform.Model, aiplatform.Endpoint]:
    """Deploys a registered model to a Vertex AI Endpoint if not already deployed.

    Args:
        model_display_name: Display name for the registered model in Vertex AI Model Registry.
        endpoint_id: Resource ID/name of the target Vertex AI Endpoint resource in infra.tf.
        project_id: GCP project ID.
        location: GCP region / location. Defaults to "us-central1".
        machine_type: Compute Engine machine type for prediction serving nodes.
        register: Whether this deployment is part of a fresh registration workflow (influences error messages).
        model: Optional pre-loaded Vertex AI Model object.

    Returns:
        A tuple of (Model, Endpoint) objects.
    """
    aiplatform.init(project=project_id, location=location)

    try:
        if not model:
            print(f"Retrieving existing Model '{model_display_name}' from Vertex AI Model Registry...")
            model = aiplatform.Model(f"projects/{project_id}/locations/{location}/models/{model_display_name}")
            print(f"Found existing Model Resource Name: {model.resource_name}")
        else:
            print(f"Using provided Model Resource Name: {model.resource_name}")

        # Specify the existing endpoint based on ID defined in infra.tf
        endpoint = aiplatform.Endpoint(f"projects/{project_id}/locations/{location}/endpoints/{endpoint_id}")
        if not endpoint:
            raise ValueError(
                f"Endpoint with ID '{endpoint_id}' was not found in project '{project_id}', location '{location}'."
            )

        # Check if the model is already deployed to the endpoint
        deployed_models = endpoint.list_models() if hasattr(endpoint, "list_models") else getattr(endpoint.gca_resource, "deployed_models", [])
        for deployed in deployed_models:
            is_same_model = (
                deployed.model == model.resource_name
                or deployed.model == model.name
                or (getattr(deployed, "display_name", None) == f"{model_display_name}-deployed")
            )
            if is_same_model:
                print(
                    f"Model '{model.display_name}' is already deployed to endpoint '{endpoint.display_name or endpoint.name}' "
                    f"(Deployed Model ID: {deployed.id}). Skipping deployment."
                )
                return model, endpoint

        # Deploy the imported model to the endpoint
        print(f"Deploying model '{model.display_name}' to endpoint '{endpoint.name}'...")
        model.deploy(
            endpoint=endpoint,
            deployed_model_display_name=f"{model_display_name}-deployed",
            machine_type=machine_type,
            traffic_percentage=100,
            sync=True,
        )
        print("Model deployment completed successfully.")
        return model, endpoint
    except NotFound as e:
        if not register:
            if e.__cause__:
                print(f"[ERROR]\n{e.__cause__}")
            print("\nHint: Have you copied the model with 'deploy_models.py --register'?\n")
            sys.exit(1)
        raise e


def deploy_bqml_model(
    source_model_name: str = None,
    model_display_name: str = None,
    endpoint_id: str = None,
    project_id: str = None,
    location: str = "us-central1",
    dataset_id: str = "cymbal_gold",
    machine_type: str = "n1-standard-2",
    register: bool = False,
):
    """Copies BQML model from source project, registers it to Vertex AI Model Registry, and deploys to Endpoint.

    Args:
        source_model_name: Name of the source BQML model (required if register is True).
        model_display_name: Display name for the registered model in Vertex AI Model Registry.
        endpoint_id: Resource ID/name of the target Vertex AI Endpoint resource in infra.tf.
        project_id: Google Cloud project ID.
        location: GCP region / location. Defaults to "us-central1".
        dataset_id: Gold dataset ID. Defaults to "cymbal_gold".
        machine_type: Compute Engine machine type for prediction serving nodes.
        register: Whether to copy and register the BQML model into Vertex AI Model Registry before deploying.
    """
    model = None
    target_display_name = model_display_name

    if register:
        if not source_model_name:
            raise ValueError("source_model_name is required to register a new model.")

        bq_exists = check_bq_model_exists(project_id, dataset_id, source_model_name)
        vertex_exists, existing_vertex_model = check_vertex_model_exists(
            project_id, location, model_display_name
        )

        print(
            f"Status for '{source_model_name}' / '{model_display_name}': "
            f"BigQuery exists={bq_exists}, Vertex AI Model Registry exists={vertex_exists}"
        )

        if bq_exists and vertex_exists:
            print(
                f"Model '{source_model_name}' already exists in BigQuery and '{model_display_name}' "
                f"exists in Vertex AI Model Registry. Skipping copy and registration."
            )
            model = existing_vertex_model
        elif bq_exists and not vertex_exists:
            print(
                f"Model '{source_model_name}' exists in BigQuery but not in Vertex AI Model Registry. "
                f"Registering model to Model Registry..."
            )
            dest_model_path = f"{project_id}:{dataset_id}.{source_model_name}"
            model = register_bqml_model(
                model_display_name=model_display_name,
                dest_model_path=dest_model_path,
                project_id=project_id,
                location=location,
            )
        elif not bq_exists and vertex_exists:
            suffix = generate_random_suffix(6)
            suffixed_bq_name = f"{source_model_name}_elevate_{suffix}"
            target_display_name = f"{model_display_name}-elevate-{suffix}"
            print(
                f"Model missing in BigQuery but '{model_display_name}' exists in Vertex AI Model Registry. "
                f"Copying to BigQuery as '{suffixed_bq_name}' and registering as '{target_display_name}'..."
            )
            dest_model_path = copy_bqml_model(
                source_model_name=source_model_name,
                target_model_name=suffixed_bq_name,
                project_id=project_id,
                dataset_id=dataset_id,
            )
            model = register_bqml_model(
                model_display_name=target_display_name,
                dest_model_path=dest_model_path,
                project_id=project_id,
                location=location,
            )
        else:  # not bq_exists and not vertex_exists
            print(
                f"Model '{source_model_name}' does not exist in BigQuery or Vertex AI Model Registry. "
                f"Copying and registering..."
            )
            dest_model_path = copy_bqml_model(
                source_model_name=source_model_name,
                target_model_name=source_model_name,
                project_id=project_id,
                dataset_id=dataset_id,
            )
            model = register_bqml_model(
                model_display_name=model_display_name,
                dest_model_path=dest_model_path,
                project_id=project_id,
                location=location,
            )

    return deploy_model_to_endpoint(
        model_display_name=target_display_name,
        endpoint_id=endpoint_id,
        project_id=project_id,
        location=location,
        machine_type=machine_type,
        register=register,
        model=model,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Deploy BQML model to Vertex AI Endpoint.")
    parser.add_argument(
        "-register",
        "--register",
        action="store_true",
        help="Register and deploy models.",
    )
    parser.add_argument(
        "--project_id",
        type=str,
        help="Google Cloud project ID.",
    )
    parser.add_argument(
        "--region",
        type=str,
        default="us-central1",
        help="GCP region.",
    )
    parser.add_argument(
        "--dataset_id",
        type=str,
        default="cymbal_gold",
        help="Gold dataset ID.",
    )
    parser.add_argument(
        "--order_anomaly_endpoint",
        type=str,
        default="order-anomaly-endpoint",
        help="Order anomaly endpoint ID.",
    )
    parser.add_argument(
        "--cashier_abuse_endpoint",
        type=str,
        default="cashier-abuse-endpoint",
        help="Cashier abuse endpoint ID.",
    )
    parser.add_argument(
        "-model",
        "--source_model_name",
        type=str,
        choices=["cashier_abuse_model", "order_anomaly_model"],
        help="Specific source BQML model name to deploy. If not provided, all models will be deployed.",
    )
    args = parser.parse_args()

    project_id = args.project_id or os.environ.get("PROJECT_ID")
    location = args.region or os.environ.get("GCP_REGION", "us-central1")
    dataset_id = args.dataset_id

    if not project_id:
        raise ValueError("Project ID must be provided via --project_id or PROJECT_ID environment variable.")

    print(f"Using project_id: '{project_id}', location: '{location}', dataset_id: '{dataset_id}'")

    order_anomaly_endpoint_name = args.order_anomaly_endpoint
    cashier_abuse_endpoint_name = args.cashier_abuse_endpoint

    models = [
        {
            "model_display_name": "model-cashier-abuse",
            "source_model_name": "cashier_abuse_model",
            "endpoint_id": cashier_abuse_endpoint_name,
        },
        {
            "model_display_name": "model-order-anomaly",
            "source_model_name": "order_anomaly_model",
            "endpoint_id": order_anomaly_endpoint_name,
        },
    ]

    if args.source_model_name:
        models = [m for m in models if m["source_model_name"] == args.source_model_name]

    for model in models:
        deploy_bqml_model(
            model_display_name=model["model_display_name"],
            source_model_name=model["source_model_name"],
            endpoint_id=model["endpoint_id"],
            project_id=project_id,
            location=location,
            dataset_id=dataset_id,
            register=args.register,
        )
