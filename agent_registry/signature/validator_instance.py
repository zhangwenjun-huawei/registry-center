# Copyright (c) 2026 Huawei Technologies Co., Ltd.
# All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
from functools import lru_cache

from agent_registry.signature.agent_card_signature_validator import AgentCardSignatureValidator
from agent_registry.signature.jwk_fetcher import JWKFetcher
from agent_registry.signature.public_key_manager import PublicKeyManager


def get_agent_card_validator() -> AgentCardSignatureValidator:
    """Get AgentCard validator singleton"""

    @lru_cache(maxsize=1)
    def _get_validator() -> AgentCardSignatureValidator:
        public_key_manager = PublicKeyManager()
        jwk_fetcher = JWKFetcher(public_key_manager)
        return AgentCardSignatureValidator(jwk_fetcher)

    return _get_validator()
